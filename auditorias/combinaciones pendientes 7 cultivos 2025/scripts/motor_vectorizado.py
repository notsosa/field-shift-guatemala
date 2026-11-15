"""Misma contabilidad del motor publicado, evaluando escenarios independientes por columnas.

No cambia las ecuaciones ni comparte agua entre escenarios. La regresión contrasta
esta implementación con el motor escalar y con resultados ya publicados.
"""
import numpy as np
from scripts import motor_hidrico_base as base

TOTAL_KEYS=['P_mm','riego_neto_mm','escorrentia_supuesta_mm','drenaje_profundo_modelo_mm','ET_potencial_cultivo_mm','ET_real_cultivo_mm','deficit_ET_mm']
SEG_KEYS=['ETc_mm','ETa_mm','deficit_mm','riego_mm','lluvia_mm','dias_Ks_menor_095','lluvia_ultimos10dias_mm']


def scenario_grid(soil_cases,runoffs,initials,irrigation):
    import itertools
    return list(itertools.product(base.LABELS,soil_cases,runoffs,initials,irrigation))


def simulate_many(rows,profile,schedule,cases,calname,seqname,keep_indices=()):
    assert len(rows)==365 and len(cases)>0
    assert all(s['end']<=base.DAYS[-1] for s in schedule)
    n=len(cases);layers=len(profile)
    caps=np.array([p['agua_disponible_mm'] for p in profile])[None,:]*np.array([c[1][2] for c in cases])[:,None]
    state=caps*np.array([c[3] for c in cases])[:,None]
    runoff=np.array([c[2] for c in cases]);root_cap=np.array([c[1][1] for c in cases]);irrigate=np.array([c[4] for c in cases],dtype=bool)
    lower=np.array([p['desde_m'] for p in profile]);width=np.array([p['hasta_m']-p['desde_m'] for p in profile])
    rain=np.array([[r['P_'+c[0]+'_mm'] for c in cases] for r in rows]);et0=np.array([r['et0_power_fao56_mm'] for r in rows])
    assert np.all(np.isfinite(rain)) and np.all(rain>=0) and np.all(np.isfinite(et0)) and np.all(et0>=0)
    totals={k:np.zeros(n) for k in TOTAL_KEYS};crop_totals=[{k:np.zeros(n) for k in SEG_KEYS} for _ in schedule]
    stress=np.zeros(n,dtype=int);mass=np.zeros(n);active=0;details=[]
    selected_days=[next(((idx,s) for idx,s in enumerate(schedule) if s['start']<=day<=s['end']),None) for day in base.DAYS]
    for index,(day,selected) in enumerate(zip(base.DAYS,selected_days)):
        before=state.sum(axis=1);precip=rain[index];overflow=precip*(1-runoff);rain_runoff=precip*runoff
        for layer in range(layers):
            add=np.minimum(caps[:,layer]-state[:,layer],overflow);state[:,layer]+=add;overflow-=add
        drain=overflow.copy()
        if selected:
            crop_index,current=selected;crop=current['crop'];kc,zr=base.kc_and_root((day-current['start']).days,current['params']);p0=current['params']['p']
        else:crop='suelo_sin_cultivo';kc,zr,p0=.20,.15,.5
        roots=np.minimum(zr,root_cap)
        rooted=np.clip((roots[:,None]-lower[None,:])/width[None,:],0,1)
        taw=(caps*rooted).sum(axis=1);available=(state*rooted).sum(axis=1)
        etc=kc*et0[index];p=min(.8,max(.1,p0+.04*(5-etc)))
        irrigation=np.where(irrigate & (available<(1-p)*taw),20.,0.) if selected else np.zeros(n)
        to_add=irrigation.copy()
        for layer in range(layers):
            add=np.minimum(caps[:,layer]-state[:,layer],to_add);state[:,layer]+=add;to_add-=add
        drain+=to_add;accessible=state*rooted;available=accessible.sum(axis=1)
        ks=np.minimum(1,available/((1-p)*taw)) if selected else np.ones(n)
        eta=np.minimum(etc*ks,available)
        # Orden de operaciones conservado: ETa * agua accesible / agua total.
        removal=np.divide(eta[:,None]*accessible,available[:,None],out=np.zeros_like(accessible),where=available[:,None]>0)
        state-=removal;after=state.sum(axis=1)
        residual=before+precip+irrigation-rain_runoff-drain-eta-after
        mass=np.maximum(mass,np.abs(residual))
        assert np.max(mass)<1e-7 and np.all(state>=-1e-8) and np.all(state<=caps+1e-8)
        for key,value in [('P_mm',precip),('riego_neto_mm',irrigation),('escorrentia_supuesta_mm',rain_runoff),('drenaje_profundo_modelo_mm',drain)]:totals[key]+=value
        if selected:
            active+=1;deficit=etc-eta;stress+=(ks<.95)
            for key,value in [('ET_potencial_cultivo_mm',etc),('ET_real_cultivo_mm',eta),('deficit_ET_mm',deficit)]:totals[key]+=value
            for key,value in [('ETc_mm',etc),('ETa_mm',eta),('deficit_mm',deficit),('riego_mm',irrigation),('lluvia_mm',precip),('dias_Ks_menor_095',(ks<.95)),('lluvia_ultimos10dias_mm',precip if (current['end']-day).days<10 else 0.)]:crop_totals[crop_index][key]+=value
        for case_index in keep_indices:
            c=cases[case_index]
            details.append({'fecha':day.isoformat(),'programa':calname,'fuente_lluvia':c[0],'secuencia':seqname,'riego_hipotetico':c[4],
                            'cultivo':crop,'P_mm':float(precip[case_index]),'ET0_mm':float(et0[index]),'Kc':float(kc),'Zr_m':float(roots[case_index]),
                            'TAW_raices_mm':float(taw[case_index]),'agua_disponible_raices_antes_ET_mm':float(available[case_index]),'Ks':float(ks[case_index]),
                            'ETc_mm':float(etc),'ETa_mm':float(eta[case_index]),'riego_neto_mm':float(irrigation[case_index]),
                            'agua_disponible_perfil_final_mm':float(after[case_index]),'residuo_balance_mm':float(residual[case_index])})
    assert active==sum((s['end']-s['start']).days+1 for s in schedule)
    results=[]
    for i,c in enumerate(cases):
        segments=[{**{k:float(v[i]) for k,v in values.items()},'cultivo':s['crop'],'inicio':s['start'].isoformat(),'fin':s['end'].isoformat()} for values,s in zip(crop_totals,schedule)]
        results.append({'calendario':calname,'secuencia':seqname,'fuente_lluvia':c[0],'suelo_escenario':c[1][0],
                        'fraccion_escorrentia_supuesta':c[2],'fraccion_agua_inicial_enero01':c[3],'riego_hipotetico':c[4],
                        'dias_con_cultivo':active,'dias_Ks_menor_095':int(stress[i]),**{k:round(float(v[i]),5) for k,v in totals.items()},
                        'ETa_sobre_ETc':round(float(totals['ET_real_cultivo_mm'][i]/totals['ET_potencial_cultivo_mm'][i]),6) if totals['ET_potencial_cultivo_mm'][i] else None,
                        'max_error_balance_mm':float(mass[i]),'segmentos':segments,'decision_compatibilidad':'requiere_evaluacion_local_y_sanitaria'})
    return results,details

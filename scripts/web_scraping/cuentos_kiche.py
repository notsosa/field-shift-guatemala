import os
import time
from urllib.parse import urljoin
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

def descargar_cuentos_kiche_con_playwright():
    # Obtener la ruta absoluta de la carpeta donde está guardado este script (.py)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Crear la carpeta local 'cuentos_kiche' dentro de esa misma ruta
    output_dir = os.path.join(script_dir, "cuentos_kiche")
    os.makedirs(output_dir, exist_ok=True)
    
    # URL principal de la antología de cuentos en K'iche'
    main_url = "https://cnbguatemala.org/wiki/Antolog%C3%ADa_de_cuentos/Cuentos_en_k%27iche%27"
    domain = "https://cnbguatemala.org"
    
    print(f"Iniciando navegador con Playwright para conectar a la antología...")
    
    with sync_playwright() as p:
        # Lanzar Chromium en segundo plano (headless=True)
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                       "AppleWebKit/537.36 (KHTML, like Gecko) "
                       "Chrome/122.0.0.0 Safari/537.36"
        )
        
        try:
            # 1. Cargar la página principal de la antología
            print(f"Navegando a: {main_url}")
            page.goto(main_url, timeout=60000)
            page.wait_for_load_state("networkidle")
            
            main_html = page.content()
            soup = BeautifulSoup(main_html, 'html.parser')
            
            # En las wikis, el contenido principal suele estar dentro de 'div.mw-parser-output'
            content_div = soup.find("div", {"class": "mw-parser-output"})
            if not content_div:
                print("No se pudo localizar el contenedor principal de contenido.")
                content_div = soup
                
            # Buscar todos los enlaces dentro del contenido
            links = content_div.find_all("a", href=True)
            
            story_urls = set()
            for link in links:
                href = link['href']
                # Filtramos para asegurarnos de que sean páginas de la antología
                if "/wiki/" in href and "Antología_de_cuentos" in href and href != "/wiki/Antolog%C3%ADa_de_cuentos/Cuentos_en_k%27iche%27":
                    full_url = urljoin(domain, href)
                    story_urls.add(full_url)
                    
            print(f"Se encontraron {len(story_urls)} enlaces a cuentos.")
            
            # 2. Iterar sobre cada cuento y extraer su texto usando la misma sesión del navegador
            for i, url in enumerate(sorted(story_urls), 1):
                try:
                    print(f"[{i}/{len(story_urls)}] Descargando: {url}")
                    page.goto(url, timeout=60000)
                    page.wait_for_load_state("networkidle")
                    
                    story_html = page.content()
                    story_soup = BeautifulSoup(story_html, 'html.parser')
                    
                    # Extraer el título de la página
                    title_element = story_soup.find("h1", {"id": "firstHeading"})
                    title = title_element.text.strip() if title_element else f"cuento_{i}"
                    
                    # Limpiar el título para usarlo como nombre de archivo válido
                    safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '_', '-')).rstrip()
                    safe_title = safe_title.replace(" ", "_")
                    
                    # Extraer los párrafos del contenido de la historia
                    story_content = story_soup.find("div", {"class": "mw-parser-output"})
                    paragraphs = story_content.find_all(['p', 'li']) if story_content else story_soup.find_all('p')
                    
                    text_to_save = f"Título: {title}\nURL: {url}\n\n"
                    for p in paragraphs:
                        text_to_save += p.text.strip() + "\n\n"
                        
                    # Guardar en un archivo de texto dentro de la ruta del script
                    file_path = os.path.join(output_dir, f"{i}_{safe_title}.txt")
                    with open(file_path, "w", encoding="utf-8") as f:
                        f.write(text_to_save)
                        
                    time.sleep(1)
                    
                except Exception as e:
                    print(f"  -> Ocurrió un error procesando {url}: {e}")
                    
            print(f"\n¡Proceso finalizado! Los cuentos han sido guardados en la carpeta:\n{output_dir}")
            
        except Exception as e:
            print(f"Ocurrió un error general con Playwright: {e}")
        finally:
            browser.close()

if __name__ == "__main__":
    descargar_cuentos_kiche_con_playwright()
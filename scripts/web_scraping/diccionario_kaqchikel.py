import os
from playwright.sync_api import sync_playwright

def descargar_webonary_kaqchikel_con_playwright():
    # Obtener la ruta absoluta de la carpeta donde está guardado este script (.py)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "diccionario_kaqchikel")
    os.makedirs(output_dir, exist_ok=True)
    
    url = "https://www.webonary.org/kaqchikel/browse/browse-vernacular/"
    
    print("Iniciando navegador real (headless) con Playwright para evitar el bloqueo 403...")
    
    with sync_playwright() as p:
        # Lanzar Chromium en segundo plano (headless=True)
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                       "AppleWebKit/537.36 (KHTML, like Gecko) "
                       "Chrome/122.0.0.0 Safari/537.36"
        )
        
        try:
            # Navegar a la URL y esperar a que la red esté inactiva (carga completa de JS)
            print(f"Navegando a: {url}")
            page.goto(url, timeout=60000)
            page.wait_for_load_state("networkidle")
            
            # Obtener el código HTML ya renderizado
            html_content = page.content()
            
            file_path = os.path.join(output_dir, "browse_kaqchikel.html")
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(html_content)
                
            print(f"¡Éxito! Página renderizada y guardada en:\n{file_path}")
            
        except Exception as e:
            print(f"Ocurrió un error durante la navegación: {e}")
        finally:
            browser.close()

if __name__ == "__main__":
    descargar_webonary_kaqchikel_con_playwright()
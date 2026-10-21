# Conectar FotoJAS con Google Drive (una sola vez, ~5 minutos)

Las fotos se suben a **tu** Google Drive, a la carpeta `FotoJAS/<nombre del evento>`.
Cada foto y cada carpeta de evento se comparten como "cualquiera con el enlace puede ver",
y ese enlace es el que aparece en el QR.

1. Entra en **https://script.google.com** con tu cuenta de Google y pulsa **Nuevo proyecto**.
2. Borra lo que haya y pega el contenido de [`google_apps_script/Code.gs`](google_apps_script/Code.gs).
3. Cambia la línea `const SECRET = 'cambia-esta-clave';` por una clave tuya (p. ej. `fotojas-2026-xk7`).
4. Guarda (icono de disco) y ponle de nombre **FotoJAS**.
5. Arriba, elige la función **autorizar** y pulsa **Ejecutar**. Google pedirá permisos:
   *Revisar permisos → tu cuenta → Configuración avanzada → Ir a FotoJAS (no seguro) → Permitir*.
   (Sale "no seguro" porque el script es tuyo y no está verificado por Google; es normal.)
6. Pulsa **Implementar → Nueva implementación**:
   - Tipo (engranaje): **Aplicación web**
   - Ejecutar como: **Yo**
   - Quién tiene acceso: **Cualquier usuario**
   - Pulsa **Implementar** y **copia la URL** que termina en `/exec`.
7. En FotoJAS: mantén pulsada la esquina superior derecha → PIN (por defecto **1234**) →
   **Google Drive y QR**:
   - Activa *Subir fotos a Google Drive*
   - Pega la URL del paso 6 y la clave del paso 3
   - Pulsa **Probar conexión**: debe aparecer el enlace de la carpeta del evento.

> Si más adelante cambias el código del script, usa **Implementar → Gestionar implementaciones → Editar → Nueva versión**
> para conservar la misma URL.

**Sin internet en el evento:** las fotos se guardan en el dispositivo y se suben solas cuando vuelve la conexión.
Mientras tanto, el QR muestra la galería del evento (si ya se probó la conexión antes).

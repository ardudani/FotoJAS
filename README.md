# FotoJAS 📸

Fotomatón para **Android (móvil/tablet)** y **Windows**: cuenta atrás, foto o collage,
montaje con marco y texto del evento, impresión automática en la **Epson XP-8600**
y QR para descargar la foto desde Google Drive.

## Descargar e instalar

Cada vez que se sube un cambio a `main`, GitHub compila la app automáticamente
(pestaña **Actions**) y publica una versión nueva en **Releases**:

- **FotoJAS.apk** → cópialo al móvil/tablet y ábrelo (acepta "instalar apps de origen desconocido").
- **FotoJAS-Windows.zip** → descomprímelo en una carpeta y abre `fotojas.exe`.

## Uso en el evento

1. Cliente: elige **Foto** o **Collage** → cuenta atrás → **¿Te gusta?** (Repetir / Me gusta)
   → **Imprimir** (con nº de copias) y/o **Ver QR** → Terminar.
2. Operador: **mantén pulsada la esquina superior derecha** de la pantalla de inicio y
   escribe el PIN (por defecto **1234**, cámbialo en Ajustes → Sistema).

## Primera configuración

| Qué | Dónde |
|---|---|
| Nombre del evento, textos, tipografía, colores | Ajustes → Evento |
| Vertical/horizontal, nº fotos del collage, marco PNG | Ajustes → Diseño |
| Cámara frontal/trasera, espejo, cuenta atrás | Ajustes → Cámara |
| Impresora, copias máximas, límite total | Ajustes → Impresión |
| Google Drive y QR | Ajustes → Google Drive y QR (ver [GUIA_GOOGLE_DRIVE.md](GUIA_GOOGLE_DRIVE.md)) |

### Impresora Epson XP-8600

- **Método "Directo por red (IPP)"** (Android y Windows, sin diálogo): escribe la IP de la impresora
  (en la Epson: *Configuración → Configuración de red → Estado de red*). Conviene fijarla en el router.
  Pulsa **Comprobar impresora** para ver tinta, papel cargado y bandejas, y **Imprimir prueba**.
- **Método "Impresora de Windows"**: usa el driver instalado. Configura en Windows la impresora con
  papel 10×15, tipo fotográfico y sin bordes.
- El dispositivo y la impresora deben estar en la **misma red WiFi** (sirve el punto de acceso del móvil o un router de viaje).

### Marcos

Diseña un PNG de **1200×1800 px** (vertical) o **1800×1200 px** (horizontal) con transparencia
donde deben verse las fotos. En Ajustes → Diseño, **Guardar plantilla guía** crea una imagen con la
posición exacta de fotos y texto para usarla de base en Canva.

## Dónde se guardan las fotos

- Android: `Android/data/es.fotojas.fotojas/files/FotoJAS/<evento>/` (accesible conectando por USB)
- Windows: `Documentos\FotoJAS\<evento>\`

## Estructura del código

```
lib/
  main.dart                 arranque, pantalla completa, tema
  settings.dart             todos los ajustes (se guardan solos)
  services/
    camera_service.dart     cámara del dispositivo
    composer.dart           montaje 10×15 a 300 ppp (fotos + texto + marco)
    ipp.dart                impresión directa por red (protocolo IPP)
    printer_service.dart    elige método de impresión
    drive_service.dart      cola de subida a Drive (reintenta sin conexión)
  ui/                       pantallas (inicio, captura, revisión, QR, ajustes)
google_apps_script/Code.gs  script para tu Google Drive
.github/workflows/build.yml compilación automática APK + Windows
```

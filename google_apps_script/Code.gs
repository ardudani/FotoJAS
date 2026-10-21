/**
 * FotoJAS · Script de subida a Google Drive
 * Pega este código en https://script.google.com y despliégalo como
 * "Aplicación web" (Ejecutar como: Yo · Acceso: Cualquier usuario).
 * Instrucciones completas en GUIA_GOOGLE_DRIVE.md
 */

// Cambia esta clave y escribe la misma en Ajustes > Google Drive de la app
const SECRET = 'cambia-esta-clave';
// Carpeta principal en tu Drive donde se crea una subcarpeta por evento
const ROOT_FOLDER_NAME = 'FotoJAS';

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    if (data.secret !== SECRET) return out({ ok: false, error: 'Clave secreta incorrecta' });

    const folder = getEventFolder(data.event || 'Evento');
    const res = { ok: true, folderUrl: folder.getUrl(), folderId: folder.getId() };

    if (data.action === 'upload') {
      const bytes = Utilities.base64Decode(data.image);
      const blob = Utilities.newBlob(bytes, 'image/jpeg', data.filename || ('foto_' + Date.now() + '.jpg'));
      const file = folder.createFile(blob);
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      res.fileId = file.getId();
      res.fileUrl = 'https://drive.google.com/file/d/' + file.getId() + '/view';
      res.downloadUrl = 'https://drive.google.com/uc?export=download&id=' + file.getId();
    }
    return out(res);
  } catch (err) {
    return out({ ok: false, error: String(err) });
  }
}

function doGet() {
  return out({ ok: true, message: 'FotoJAS script activo' });
}

function getEventFolder(eventName) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const root = findOrCreate(DriveApp.getRootFolder(), ROOT_FOLDER_NAME);
    const folder = findOrCreate(root, eventName);
    if (folder.getSharingAccess() !== DriveApp.Access.ANYONE_WITH_LINK) {
      folder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    }
    return folder;
  } finally {
    lock.releaseLock();
  }
}

function findOrCreate(parent, name) {
  const it = parent.getFoldersByName(name);
  return it.hasNext() ? it.next() : parent.createFolder(name);
}

function out(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/** Ejecuta esta función una vez desde el editor para conceder permisos. */
function autorizar() {
  const f = getEventFolder('Prueba');
  Logger.log('Carpeta de prueba: ' + f.getUrl());
}

// Cloud Functions для Asem Pro.
// Содержат серверные операции, недоступные клиенту: смена пароля водителя
// и удаление его аккаунта в Firebase Auth (требуют Admin SDK).
//
// Деплой: firebase deploy --only functions  (проект должен быть на плане Blaze).

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();

// Проверяем, что вызывающий — администратор (есть документ admins/{uid}).
async function assertAdmin(auth) {
  if (!auth) {
    throw new HttpsError('unauthenticated', 'Требуется вход администратора.');
  }
  const doc = await admin.firestore().collection('admins').doc(auth.uid).get();
  if (!doc.exists) {
    throw new HttpsError('permission-denied', 'Действие доступно только администратору.');
  }
}

// Установить новый пароль водителю (Firebase Auth).
exports.setDriverPassword = onCall(async (request) => {
  await assertAdmin(request.auth);

  const driverUid = request.data && request.data.driverUid;
  const newPassword = request.data && request.data.newPassword;

  if (!driverUid || typeof newPassword !== 'string' || newPassword.length < 6) {
    throw new HttpsError(
      'invalid-argument',
      'Нужны driverUid и пароль не короче 6 символов.'
    );
  }

  await admin.auth().updateUser(driverUid, { password: newPassword });
  return { ok: true };
});

// Полностью удалить аккаунт водителя: Firebase Auth + документ в Firestore.
exports.deleteDriverAccount = onCall(async (request) => {
  await assertAdmin(request.auth);

  const driverUid = request.data && request.data.driverUid;
  if (!driverUid) {
    throw new HttpsError('invalid-argument', 'Нужен driverUid.');
  }

  try {
    await admin.auth().deleteUser(driverUid);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  await admin.firestore().collection('drivers').doc(driverUid).delete();
  return { ok: true };
});

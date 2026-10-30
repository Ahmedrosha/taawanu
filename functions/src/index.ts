// نقطة الدخول: كل الـFunctions اللي بتترفع على Firebase.
// المنطقة والإعدادات العامة في common.ts.
export {
  createGroup, updateGroupSettings, leaveGroup, removeMember, setRole, moveMember, transferAdmin, deleteGroup, deleteAccount,
} from './groups';
export {
  createInvite, revokeInvite, previewInvite, previewPublicGroup, joinGroup, joinPublicGroup,
} from './invites';
export {
  startKhatma, cycleTick, updateProgress, claimPortion, assignPortion, completePortion, recordProgress,
} from './cycles';

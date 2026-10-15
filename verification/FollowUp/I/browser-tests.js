/* Real DOM/controller, synthetic transport and BaseView. No Emby server or Google. */
class BaseView {
    constructor(view) { this.view = view; }
    onResume() {} onPause() {} destroy() {}
}
let Controller;
window.define = (dependencies, factory) => { Controller = factory(BaseView); };
const results = [];
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const assert = (name, condition) => { results.push({ Name: name, Passed: !!condition }); if (!condition) throw Error(name); };
const ownerA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', ownerB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const profile = (owner = ownerA, revision = 1) => ({ OwnerUserId: owner, Revision: revision, Channels: ['UCaaaaaaaaaaaaaaaaaaaaaa'], HasApiKey: true, State: 'Active' });
let pending, requests, api, view, controller;
function setup() {
    if (controller) controller.destroy({});
    document.querySelector('#fixture').innerHTML = window.fixtureHtml;
    view = document.querySelector('#fixture').firstElementChild;
    pending = []; requests = [];
    api = { owner: ownerA, getCurrentUserId() { return this.owner; }, getUrl: path => path,
        ajax(options) { requests.push(options); return new Promise((resolve, reject) => pending.push({ options, resolve, reject })); } };
    window.ApiClient = api;
    controller = new Controller(view, {}); controller.active = true;
    controller.render(profile()); controller.saveButton.disabled = false;
}
async function runBaseline() {
    setup(); const switched = controller.loadJob(); api.owner = ownerB;
    pending.shift().resolve({OwnerUserId:ownerB,State:'Ready',TotalVideos:777}); await switched;
    assert('baseline-late-job-painted-after-account-switch', controller.jobStatus.textContent.includes('777') && !!controller.profile);
    setup(); controller.jobStatus.textContent = 'private ready status'; controller.onPause({});
    assert('baseline-pause-retains-private-job-status', controller.jobStatus.textContent === 'private ready status');
    setup(); const stale = controller.loadJob(), fresh = controller.loadJob();
    pending[1].resolve({OwnerUserId:ownerA,State:'Ready',TotalVideos:2}); await fresh;
    pending[0].resolve({OwnerUserId:ownerA,State:'Ready',TotalVideos:888}); await stale;
    assert('baseline-old-job-response-overwrites-new', controller.jobStatus.textContent.includes('888'));
    controller.destroy({});
}
async function runTests() {
    for (const state of ['Disabled','Idle','WaitingForSettings','Queued','Cleaning','Fetching','Buffering','Publishing','Ready','Cancelled','Deleted','Failed']) {
        setup(); const task = controller.loadJob(); pending.shift().resolve({OwnerUserId:ownerA,ProfileRevision:1,State:state,CompletedVideos:2,TotalVideos:3}); await task;
        assert('visible-state-' + state, controller.jobStatus.textContent.length > 10 && controller.jobStatus.textContent !== 'Jobbstatus er ikke tilgjengelig.');
    }
    for (const code of ['YouTubeKeyRejected','MediaToolsUnavailable','InvalidServerSettings','StorageBudgetExceeded','StorageUnavailable','YouTubeQuotaExceeded','YouTubeRequestFailed','CleanupFailed','RefreshFailed','StatusUnavailable','UnknownPrivateFailure']) {
        setup(); const task = controller.loadJob();
        pending.shift().resolve({ OwnerUserId: ownerA, ProfileRevision: 1, State: 'Failed', ErrorCode: code, Details: '<script>private-key</script>' }); await task;
        assert('sanitized-browser-error-' + code, controller.jobStatus.textContent.length > 20 && !view.textContent.includes('private-key') && !controller.jobStatus.querySelector('script'));
    }
    setup(); controller.key.value = 'synthetic-key';
    const firstSave = controller.save(); controller.save(); controller.load();
    assert('double-save-and-reload-no-extra-request', requests.length === 1 && controller.key.value === '');
    assert('expected-revision-no-owner-parameter', JSON.parse(requests[0].data).ExpectedRevision === 1 && !('OwnerUserId' in JSON.parse(requests[0].data)));
    pending.shift().resolve(profile(ownerA, 2)); await firstSave; pending.shift().resolve({OwnerUserId:ownerA, ProfileRevision:2, State:'Ready', TotalVideos:1}); await flush();
    assert('save-readback', controller.profile.Revision === 2 && controller.jobStatus.textContent.includes('1 videoer'));
    setup(); const conflict = controller.save(); pending.shift().reject({status:409}); await conflict;
    assert('revision-conflict-blocks-save-delete', !controller.profile && controller.saveButton.disabled && controller.deleteButton.disabled && controller.status.textContent.includes('annen økt'));
    setup(); await controller.deleteCollection(); assert('delete-confirmation-no-request', requests.length === 0);
    const deletion = controller.deleteCollection(); controller.deleteCollection(); assert('double-delete-single-request', requests.length === 1);
    pending.shift().resolve({...profile(ownerA,2), State:'Deleted', Channels:[], HasApiKey:false}); await deletion;
    assert('delete-readback-clears-fields', controller.channels.value === '' && controller.key.value === '' && controller.deleteButton.disabled);
    setup(); controller.load(); api.owner = ownerB; pending.shift().resolve(profile()); await flush();
    assert('late-profile-account-switch-clears-private-fields', !controller.profile && controller.channels.value === '' && controller.keyStatus.textContent === '');
    setup(); const oldJob = controller.loadJob(); api.owner = ownerB; pending.shift().resolve({OwnerUserId:ownerB,State:'Ready',TotalVideos:777}); await oldJob;
    assert('late-job-switch-rejects-even-new-owner-response', !controller.profile && !controller.jobStatus.textContent.includes('777') && !controller.jobTimer);
    setup(); const oldServer = controller.loadJob(); window.ApiClient = {...api}; pending.shift().resolve({OwnerUserId:ownerA,State:'Ready',TotalVideos:999}); await oldServer;
    assert('late-job-server-switch', !controller.jobStatus.textContent.includes('999') && !controller.profile);
    setup(); window.ApiClient = {...api}; await controller.loadJob();
    assert('server-switch-before-poll-no-stale-profile-request', requests.length === 0 && !controller.profile && controller.channels.value === '');
    setup(); const switchedError = controller.loadJob(); api.owner = ownerB; pending.shift().reject({status:500}); await switchedError;
    assert('late-job-error-clears-on-account-switch', !controller.profile && controller.channels.value === '' && !controller.jobTimer);
    setup(); const stale = controller.loadJob(); const fresh = controller.loadJob(); pending[1].resolve({OwnerUserId:ownerA,ProfileRevision:1,State:'Ready',TotalVideos:2}); await fresh;
    pending[0].resolve({OwnerUserId:ownerA,ProfileRevision:1,State:'Ready',TotalVideos:888}); await stale;
    assert('out-of-order-job-response', controller.jobStatus.textContent.includes('2 videoer') && !controller.jobStatus.textContent.includes('888'));
    setup(); const paused = controller.loadJob(); controller.onPause({}); pending.shift().resolve({OwnerUserId:ownerA,State:'Ready',TotalVideos:999}); await paused;
    assert('navigation-stops-poll-and-late-response', !controller.jobTimer && !controller.profile && !controller.jobStatus.textContent.includes('999'));
    for (const status of [401,403]) {
        setup(); const expired = controller.loadJob(); pending.shift().reject({status}); await expired;
        assert('session-' + status + '-stops-poll-clears-fields', !controller.jobTimer && !controller.profile && controller.channels.value === '' && controller.jobStatus.textContent.includes('Logg inn'));
    }
    setup(); const newer = controller.loadJob(); pending.shift().resolve({OwnerUserId:ownerA,ProfileRevision:2,State:'Ready',TotalVideos:5}); await newer;
    assert('other-tab-job-revision-not-painted', controller.jobStatus.textContent.includes('annen økt') && !controller.jobTimer);
    setup(); const switchedSave = controller.save(); api.owner = ownerB; pending.shift().reject({status:500}); await switchedSave;
    assert('late-save-error-account-switch-clears-fields', !controller.profile && controller.channels.value === '' && controller.saveButton.disabled);
    setup(); controller.jobStatus.textContent = 'private ready status'; controller.onPause({});
    assert('pause-clears-existing-job-status', controller.jobStatus.textContent === '');
    setup(); await controller.deleteCollection(); controller.cancelDelete();
    assert('cancel-delete-no-server-mutation', !controller.deletePending && requests.length === 0);
    await controller.deleteCollection(); const deleteConflict = controller.deleteCollection(); pending.shift().reject({status:409}); await deleteConflict;
    assert('delete-conflict-blocks-mutations', !controller.profile && controller.saveButton.disabled && controller.deleteButton.disabled);
    setup(); const retainKey = controller.save();
    assert('blank-key-retains-server-key', !('ApiKey' in JSON.parse(pending[0].options.data)) && !('ClearApiKey' in JSON.parse(pending[0].options.data)));
    pending.shift().resolve(profile(ownerA,2)); await retainKey;
    setup(); controller.clearKey.checked = true; const clearKey = controller.save();
    assert('clear-key-explicit-no-global-fallback', JSON.parse(pending[0].options.data).ClearApiKey === true && !('ApiKey' in JSON.parse(pending[0].options.data)));
    pending.shift().resolve({...profile(ownerA,2),HasApiKey:false}); await clearKey;
    assert('cleared-key-readback', controller.keyStatus.textContent === 'Ingen nøkkel er lagret.');
    setup(); const wrongOwner = controller.load(); pending.shift().resolve(profile(ownerB)); await wrongOwner;
    assert('foreign-profile-response-rejected', !controller.profile && controller.channels.value === '' && controller.saveButton.disabled);
    setup();
    const secondView = view.cloneNode(true); document.querySelector('#fixture').appendChild(secondView);
    const secondTab = new Controller(secondView, {}); secondTab.active = true; secondTab.render(profile());
    const tab1 = controller.save(), tab2 = secondTab.save();
    assert('two-tabs-send-same-expected-revision', pending.slice(0,2).every(p=>JSON.parse(p.options.data).ExpectedRevision === 1));
    pending.shift().resolve(profile(ownerA,2)); pending.shift().reject({status:409}); await Promise.all([tab1,tab2]);
    assert('two-tabs-winning-readback-losing-conflict', controller.profile.Revision === 2 && !secondTab.profile && secondTab.saveButton.disabled);
    secondTab.destroy({});
    controller.destroy({});
    await new Promise((done, reject) => { const script = document.createElement('script'); script.src = '/admin.js'; script.onload = done; script.onerror = reject; document.head.appendChild(script); });
    document.querySelector('#fixture').innerHTML = window.adminHtml;
    view = document.querySelector('#fixture').firstElementChild;
    controller = new Controller(view, {}); pending = []; requests = []; api.owner = ownerA; window.ApiClient = api;
    for (const [id, value] of [['numPersonalYouTubeMaxVideos','50'],['numPersonalYouTubeMaxVideoMiB','512'],['numPersonalYouTubeMaxCollectionMiB','2048'],['numPersonalYouTubeMaxStorageMiB','10240']]) view.querySelector('#'+id).value = value;
    const serverStatus = controller.checkPersonalServer();
    pending.shift().resolve({AlphaEnabled:true, WorkerRunning:false, Creation:{Installed:false},References:{Installed:true},Lists:{Installed:true},MediaToolsAvailable:false,Details:'private-server-path'}); await serverStatus;
    assert('admin-disabled-worker-missing-controls-tools-restart', view.textContent.includes('Worker: stopped') && view.textContent.includes('controls: unavailable') && view.textContent.includes('files: missing') && !view.textContent.includes('private-server-path'));
    const pausedAdmin = controller.checkPersonalServer(); controller.onPause({}); pending.shift().resolve({AlphaEnabled:true,WorkerRunning:true}); await pausedAdmin;
    assert('admin-late-status-after-navigation', view.querySelector('.ytPersonalServerStatus').textContent === '');
    for (const invalid of ['', '0', '10001', '1.5']) {
        view.querySelector('#numPersonalYouTubeMaxVideos').value = invalid; const count = requests.length; controller.saveData(view);
        assert('admin-invalid-video-count-' + (invalid || 'empty'), requests.length === count && view.querySelector('#youtubeConfigurationStatus').textContent.includes('Invalid'));
    }
    view.querySelector('#numPersonalYouTubeMaxVideos').value = '50'; view.querySelector('#numPersonalYouTubeMaxCollectionMiB').value = '1';
    let count = requests.length; controller.saveData(view); assert('admin-video-collection-relation', requests.length === count);
    view.querySelector('#numPersonalYouTubeMaxCollectionMiB').value = '2048'; view.querySelector('#numPersonalYouTubeMaxStorageMiB').value = '1024';
    count = requests.length; controller.saveData(view); assert('admin-collection-storage-relation', requests.length === count);
    view.querySelector('#numPersonalYouTubeMaxStorageMiB').value = '10240'; controller.saveData(view);
    assert('admin-valid-save-bytes', JSON.parse(pending[0].options.data).PersonalYouTubeMaxVideoBytes === 536870912);
    pending.shift().resolve({Saved:true}); await flush();
    assert('admin-save-reminds-restart', view.querySelector('#youtubeConfigurationStatus').textContent.includes('Restart Emby'));
}

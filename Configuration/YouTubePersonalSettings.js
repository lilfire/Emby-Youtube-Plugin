define(['baseView', 'emby-input', 'emby-textarea', 'emby-button', 'emby-checkbox'], function (BaseView) {
    'use strict';
    function currentClient() {
        return window.ApiClient || (window.Dashboard && Dashboard.getCurrentApiClient && Dashboard.getCurrentApiClient());
    }
    function ownerId(api) { return String(api.getCurrentUserId() || '').replace(/-/g, '').toLowerCase(); }
    function sameOwner(api, profile) {
        return ownerId(api) === String(profile.OwnerUserId || '').replace(/-/g, '').toLowerCase();
    }
    return class extends BaseView {
        constructor(view, params) {
            super(view, params);
            this.profile = null;
            this.active = false;
            this.sequence = 0;
            this.busy = false;
            this.jobTimer = null;
            this.jobStatus = view.querySelector('.ytPersonalAvailability');
            this.form = view.querySelector('.ytPersonalForm');
            this.key = view.querySelector('#ytPersonalApiKey');
            this.channels = view.querySelector('#ytPersonalChannels');
            this.clearKey = view.querySelector('.ytPersonalClearKey');
            this.saveButton = view.querySelector('.ytPersonalSave');
            this.deleteButton = view.querySelector('.ytPersonalDelete');
            this.cancelDeleteButton = view.querySelector('.ytPersonalCancelDelete');
            this.deletePending = false;
            this.status = view.querySelector('.ytPersonalStatus');
            this.keyStatus = view.querySelector('.ytPersonalKeyStatus');
            this.submit = event => { event.preventDefault(); this.save(); };
            this.reload = () => this.load();
            this.remove = () => this.deleteCollection();
            this.cancelDelete = () => { this.resetDelete(); this.status.textContent = ''; };
            this.form.addEventListener('submit', this.submit);
            view.querySelector('.ytPersonalReload').addEventListener('click', this.reload);
            this.deleteButton.addEventListener('click', this.remove);
            this.cancelDeleteButton.addEventListener('click', this.cancelDelete);
        }
        onResume(options) { super.onResume(options); this.active = true; this.load(); }
        onPause(options) {
            clearTimeout(this.jobTimer); this.jobTimer = null;
            this.active = false; this.sequence++; this.profile = null; this.busy = false;
            this.key.value = ''; this.channels.value = ''; this.clearKey.checked = false;
            this.keyStatus.textContent = ''; this.status.textContent = ''; this.saveButton.disabled = true;
            this.resetDelete(); this.deleteButton.disabled = true;
            super.onPause(options);
        }
        render(profile) {
            this.resetDelete();
            this.profile = profile;
            this.channels.value = (profile.Channels || []).join('\n');
            this.key.value = ''; this.clearKey.checked = false;
            this.keyStatus.textContent = profile.HasApiKey ? 'En nøkkel er lagret. La feltet stå tomt for å beholde den.' : 'Ingen nøkkel er lagret.';
            this.deleteButton.disabled = !profile.Revision || profile.State === 'Deleted';
        }
        resetDelete() {
            this.deletePending = false;
            this.deleteButton.textContent = 'Slett samlingen';
            this.cancelDeleteButton.hidden = true;
        }
        async load() {
            const api = currentClient(), sequence = ++this.sequence;
            this.profile = null; this.key.value = ''; this.saveButton.disabled = true;
            this.resetDelete(); this.deleteButton.disabled = true;
            this.status.textContent = 'Laster inn…';
            if (!api || !ownerId(api)) { this.status.textContent = 'Logg inn for å endre YouTube-innstillingene.'; return; }
            try {
                const profile = await api.ajax({ type: 'GET', url: api.getUrl('YouTubePlugin/MyProfile'), dataType: 'json' });
                if (!this.active || sequence !== this.sequence) return;
                if (!sameOwner(api, profile)) { this.status.textContent = 'Brukeren er endret. Last inn på nytt.'; return; }
                this.render(profile); this.status.textContent = ''; this.busy = false; this.saveButton.disabled = false;
                this.loadJob();
            } catch (error) {
                if (this.active && sequence === this.sequence) this.status.textContent = 'Kunne ikke hente innstillingene. Prøv igjen.';
            }
        }
        async loadJob() {
            clearTimeout(this.jobTimer); this.jobTimer = null;
            const api = currentClient(), sequence = this.sequence;
            if (!this.active || !api || !this.profile || !sameOwner(api, this.profile)) return;
            try {
                const job = await api.ajax({ type: 'GET', url: api.getUrl('YouTubePlugin/MyJob'), dataType: 'json' });
                if (!this.active || sequence !== this.sequence || !sameOwner(api, job)) return;
                const messages = {
                    Disabled: 'Personlige biblioteker er ikke aktivert på serveren.',
                    Idle: 'Lagre nøkkel og kanaler for å opprette biblioteket.',
                    WaitingForSettings: 'Legg inn API-nøkkel og minst én kanal for å starte.',
                    Queued: 'Oppdateringen står i kø.',
                    Cleaning: 'Rydder den tidligere samlingen…',
                    Fetching: 'Henter videoer fra kanalene dine…',
                    Buffering: 'Klargjør videoer: ' + job.CompletedVideos + ' av ' + job.TotalVideos + '.',
                    Publishing: 'Oppdaterer Emby-biblioteket…',
                    Ready: 'Biblioteket er klart med ' + job.TotalVideos + ' videoer.',
                    Cancelled: 'Oppdateringen ble avbrutt. Lagre for å prøve igjen.',
                    Deleted: 'Den personlige samlingen er slettet.',
                    Failed: 'Oppdateringen mislyktes. Kontroller innstillingene og prøv igjen.'
                };
                const errors = {
                    MediaToolsUnavailable: 'Administrator må konfigurere yt-dlp, FFmpeg og Node.js på serveren.',
                    InvalidServerSettings: 'Administrator må kontrollere størrelsesgrensene for personlig YouTube.',
                    StorageBudgetExceeded: 'Serverens lagringsbudsjett for personlig YouTube er brukt opp. Kontakt administrator.',
                    StorageUnavailable: 'Den personlige medielagringen er ikke tilgjengelig. Kontakt administrator.',
                    YouTubeQuotaExceeded: 'YouTube-kvoten for nøkkelen din er brukt opp. Prøv igjen når kvoten er tilgjengelig.',
                    YouTubeKeyRejected: 'YouTube avviste nøkkelen. Kontroller at YouTube Data API v3 er aktivert og at nøkkelen tillater serveren.',
                    YouTubeRequestFailed: 'Kunne ikke hente kanalene fra YouTube. Kontroller nøkkelen og prøv igjen.'
                };
                this.jobStatus.textContent = (job.State === 'Failed' && errors[job.ErrorCode]) || messages[job.State] || 'Jobbstatus er ikke tilgjengelig.';
            } catch (error) {
                if (this.active && sequence === this.sequence) this.jobStatus.textContent = 'Kunne ikke hente jobbstatus.';
            } finally {
                if (this.active && sequence === this.sequence) this.jobTimer = setTimeout(() => this.loadJob(), 3000);
            }
        }
        async save() {
            const api = currentClient();
            if (this.busy || !this.profile || !api || !sameOwner(api, this.profile)) {
                this.status.textContent = 'Last inn innstillingene på nytt før du lagrer.'; return;
            }
            const channels = [...new Set(this.channels.value.split(/\r?\n/).map(value => value.trim()).filter(Boolean))];
            if (channels.length > 100 || channels.some(value => !/^UC[A-Za-z0-9_-]{22}$/.test(value))) {
                this.status.textContent = 'Bruk gyldige kanal-ID-er som begynner med UC, én per linje.'; return;
            }
            const body = { ExpectedRevision: this.profile.Revision, Channels: channels };
            if (this.clearKey.checked) body.ClearApiKey = true;
            else if (this.key.value) body.ApiKey = this.key.value;
            this.key.value = ''; this.busy = true; this.saveButton.disabled = true;
            this.resetDelete(); this.deleteButton.disabled = true;
            const sequence = ++this.sequence;
            this.status.textContent = 'Lagrer…';
            try {
                const profile = await api.ajax({ type: 'POST', url: api.getUrl('YouTubePlugin/MyProfile'), data: JSON.stringify(body), contentType: 'application/json', dataType: 'json' });
                if (!this.active || sequence !== this.sequence) return;
                if (!sameOwner(api, profile)) { this.profile = null; this.status.textContent = 'Brukeren er endret. Last inn på nytt.'; return; }
                this.render(profile); this.status.textContent = 'Lagret. Biblioteket oppdateres når personlig YouTube er aktivert.';
                this.loadJob();
            } catch (error) {
                if (this.active && sequence === this.sequence) {
                    const status = error && (error.status || error.statusCode);
                    if (status === 409) { this.profile = null; this.status.textContent = 'Innstillingene er endret i en annen økt. Last inn på nytt.'; }
                    else this.status.textContent = 'Kunne ikke lagre. Skriv inn nøkkelen på nytt hvis den skal endres.';
                }
            } finally {
                delete body.ApiKey;
                if (this.active && sequence === this.sequence) { this.busy = false; this.saveButton.disabled = !this.profile; this.deleteButton.disabled = !this.profile || !this.profile.Revision || this.profile.State === 'Deleted'; }
            }
        }
        async deleteCollection() {
            const api = currentClient();
            if (this.busy || !this.profile || !this.profile.Revision || this.profile.State === 'Deleted' || !api || !sameOwner(api, this.profile)) return;
            if (!this.deletePending) {
                this.deletePending = true;
                this.deleteButton.textContent = 'Bekreft sletting'; this.cancelDeleteButton.hidden = false;
                this.status.textContent = 'Biblioteket, bufrede videoer, kanalvalg og lagret nøkkel slettes. Bekreft for å fortsette.';
                return;
            }
            const body = { ExpectedRevision: this.profile.Revision }, sequence = ++this.sequence;
            this.busy = true; this.saveButton.disabled = true; this.deleteButton.disabled = true;
            this.resetDelete(); this.status.textContent = 'Sletter…';
            try {
                const profile = await api.ajax({ type: 'POST', url: api.getUrl('YouTubePlugin/MyProfile/Delete'), data: JSON.stringify(body), contentType: 'application/json', dataType: 'json' });
                if (!this.active || sequence !== this.sequence) return;
                if (!sameOwner(api, profile)) { this.profile = null; this.status.textContent = 'Brukeren er endret. Last inn på nytt.'; return; }
                this.render(profile); this.status.textContent = 'Samlingen er slettet. Serveren rydder biblioteket og filene.';
                this.loadJob();
            } catch (error) {
                if (this.active && sequence === this.sequence) {
                    const status = error && (error.status || error.statusCode);
                    if (status === 409) { this.profile = null; this.status.textContent = 'Innstillingene er endret. Last inn på nytt før sletting.'; }
                    else this.status.textContent = 'Kunne ikke slette samlingen. Prøv igjen.';
                }
            } finally {
                if (this.active && sequence === this.sequence) { this.busy = false; this.saveButton.disabled = !this.profile; this.deleteButton.disabled = !this.profile || !this.profile.Revision || this.profile.State === 'Deleted'; }
            }
        }
        destroy(options) {
            clearTimeout(this.jobTimer); this.jobTimer = null;
            this.active = false; this.sequence++; this.key.value = ''; this.profile = null;
            this.form.removeEventListener('submit', this.submit);
            this.view.querySelector('.ytPersonalReload').removeEventListener('click', this.reload);
            this.deleteButton.removeEventListener('click', this.remove);
            this.cancelDeleteButton.removeEventListener('click', this.cancelDelete);
            super.destroy(options);
        }
    };
});

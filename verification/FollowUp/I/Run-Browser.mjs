import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {spawn, execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
const root = resolve(import.meta.dirname, '../../..');
const html = await readFile(root + '/Configuration/YouTubePersonalSettings.html','utf8');
const tests = await readFile(import.meta.dirname + '/browser-tests.js','utf8');
const baseline = process.argv.includes('--baseline');
const controller = baseline ? execFileSync('git', ['show','HEAD:Configuration/YouTubePersonalSettings.js'], {cwd:root,encoding:'utf8'}) : await readFile(root + '/Configuration/YouTubePersonalSettings.js','utf8');
const adminSource = await readFile(root + '/Configuration/YouTubeConfiguration.js','utf8');
const adminHtml = await readFile(root + '/Configuration/YouTubeConfiguration.html','utf8');
const page = '<!doctype html><meta charset="utf-8"><div id="fixture"></div><pre id="result"></pre><script>' + tests.replace(/<\/script/gi, '<\\/script') + '\nwindow.fixtureHtml=' + JSON.stringify(html) + ';\n' + controller + '\nrunTests().then(()=>{document.querySelector("#result").textContent=JSON.stringify({Completed:true,Results:results});}).catch(error=>{document.querySelector("#result").textContent=JSON.stringify({Completed:false,Error:error.message,Results:results});});</script>';
const server = createServer((request,response)=> {
    if (request.url === '/admin.js') { response.setHeader('Content-Type','text/javascript'); response.end(adminSource); return; }
    response.setHeader('Content-Type','text/html; charset=utf-8'); response.end(page.replace('window.fixtureHtml=', 'window.adminHtml='+JSON.stringify(adminHtml)+';window.fixtureHtml=').replace('runTests().then', (baseline ? 'runBaseline()' : 'runTests()')+'.then'));
});
await new Promise(done=>server.listen(18217,'127.0.0.1',done));
const profile = root + '/bin/followup-i-edge'; await mkdir(profile,{recursive:true});
const edge = spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', ['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--user-data-dir='+profile,'--dump-dom','--virtual-time-budget=10000','http://127.0.0.1:18217/']);
let output = ''; edge.stdout.on('data',data=>output+=data); edge.stderr.resume();
const code = await new Promise(done=>edge.on('exit',done)); server.close();
const match = output.match(/<pre id="result">([^<]*)<\/pre>/);
if (!match) throw Error('No browser test result; exit=' + code);
const result = JSON.parse(match[1].replace(/&quot;/g,'"').replace(/&amp;/g,'&').replace(/&gt;/g,'>').replace(/&lt;/g,'<'));
result.Browser = 'Microsoft Edge headless'; result.Transport = 'synthetic promises; real production controller and DOM';
await writeFile(import.meta.dirname+(baseline ? '/BASELINE-EVIDENCE.json' : '/BROWSER-EVIDENCE.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({Completed:result.Completed,Checks:result.Results.length,Error:result.Error}));
if (!result.Completed) process.exitCode = 1;

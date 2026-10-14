import base64,json,sqlite3,subprocess,time,uuid,pathlib,shutil
CONFIG=pathlib.Path("/srv/dev-disk-by-uuid-f02cbf33-574c-4779-8aac-21508166ad72/appdata/emby/config")
stamp="privacy-verification-"+uuid.uuid4().hex
root=CONFIG/stamp
created_users=[]; created_libs=[]; created_jobs=[]; devices=[]; observations=[]
c=sqlite3.connect("file:"+str(CONFIG/"data/authentication.db")+"?mode=ro",uri=True)
admin=c.execute("select AccessToken from Tokens_2 where IsActive=1 and UserId is null limit 1").fetchone()[0];c.close()
def request(path,method="GET",body=None,token=admin,extra=None,binary=False):
    conf={"url":"http://127.0.0.1:8096/emby/"+path,"request":method,"max-time":"6","silent":None,"show-error":None,"write-out":"\\n%{http_code}"}
    lines=[k if v is None else k+" = "+json.dumps(v) for k,v in conf.items()]
    lines.append("header = "+json.dumps("X-Emby-Token: "+token))
    if body is not None:
        lines += ["header = "+json.dumps("Content-Type: application/json"),"data = "+json.dumps(json.dumps(body))]
    for k,v in (extra or {}).items():lines.append("header = "+json.dumps(k+": "+v))
    r=subprocess.run(["docker","exec","-i","emby_backup","curl","--config","-"],input=("\n".join(lines)+"\n").encode(),capture_output=True,timeout=8)
    if r.returncode:raise RuntimeError("Transport failure on "+path.split("?")[0])
    data,code=r.stdout.rsplit(b"\n",1);status=int(code)
    return status,(data if binary else (json.loads(data) if data else None))
def call(path,method="GET",body=None,token=admin,extra=None):
    status,data=request(path,method,body,token,extra)
    if status<200 or status>=300:raise RuntimeError("HTTP "+str(status)+" on "+path.split("?")[0])
    return data
def record(label,**data):observations.append(dict(Label=label,**data))
try:
    info=call("System/Info")
    assert info["Id"]=="9de3ec0658c34d968af80d6c1962650e" and info["Version"]=="4.10.1.0"
    record("Main server identity",ServerName=info["ServerName"],Version=info["Version"])
    root.mkdir(exist_ok=False); states={}
    for owner in ("a","b"):
        folder=root/owner;folder.mkdir();(folder/("Synthetic_"+owner+".mp4")).write_bytes(base64.b64decode(SAMPLE))
        name=stamp+"-"+owner
        call("Library/VirtualFolders","POST",{"Name":name,"CollectionType":"homevideos","Paths":["/config/"+stamp+"/"+owner],"RefreshLibrary":False,"LibraryOptions":{"EnableRealtimeMonitor":False,"SaveLocalMetadata":False,"EnableChapterImageExtraction":False,"ExtractChapterImagesDuringLibraryScan":False,"TypeOptions":[{"Type":"Video","MetadataFetchers":[],"ImageFetchers":[]}]}})
        lib=next(x for x in call("Library/VirtualFolders/Query")["Items"] if x["Name"]==name);created_libs.append(lib["ItemId"])
        user=call("Users/New","POST",{"Name":name});created_users.append(user["Id"])
        policy=user["Policy"];policy.update(IsAdministrator=False,EnableAllFolders=False,EnabledFolders=[lib["Guid"]],EnableAllChannels=False,EnabledChannels=[],EnableAllDevices=True,EnableContentDownloading=True,EnableRemoteControlOfOtherUsers=False,EnableMediaDeletion=False)
        call("Users/"+user["Id"]+"/Policy","POST",policy)
        back=call("Users/"+user["Id"])["Policy"];assert not back["IsAdministrator"] and not back["EnableAllFolders"] and back["EnabledFolders"]==[lib["Guid"]]
        device=name;devices.append(device)
        session=call("Users/AuthenticateByName","POST",{"Username":name,"Pw":""},extra={"Authorization":'MediaBrowser Client="Privacy verification", Device="Synthetic test", DeviceId="'+device+'", Version="1.0"'})
        assert session["User"]["Id"]==user["Id"]
        token=session["AccessToken"]
        call("Sessions/Capabilities/Full","POST",{"Id":session["SessionInfo"]["Id"],"SupportsSync":True,"PlayableMediaTypes":["Video"],"SupportedCommands":[]},token)
        states[owner]={"user":user["Id"],"token":token,"lib":lib["ItemId"],"device":device}
        call("Items/"+lib["ItemId"]+"/Refresh?Recursive=true&MetadataRefreshMode=FullRefresh&ImageRefreshMode=ValidationOnly","POST")
    deadline=time.monotonic()+10
    while True:
        for s in states.values():
            items=call("Items?ParentId="+s["lib"]+"&Recursive=true&IncludeItemTypes=Video")["Items"]
            if len(items)==1:s["item"]=items[0]["Id"]
        if all("item" in s for s in states.values()):break
        if time.monotonic()>deadline:raise RuntimeError("Synthetic scan timeout")
        time.sleep(.3)
    for owner,s in states.items():
        targets=call("Sync/Targets?UserId="+s["user"],token=s["token"]);assert any(x["Id"]==s["device"] for x in targets)
        opts=call("Sync/Options?UserId="+s["user"]+"&ItemIds="+s["item"],token=s["token"])
        record("Own Sync options "+owner,Fields=list(opts.keys()) if isinstance(opts,dict) else [])
        result=call("Sync/Jobs","POST",{"TargetId":s["device"],"ItemIds":[s["item"]],"Name":stamp+"-"+owner,"UserId":s["user"],"Quality":"Original","Profile":"Original","Downloaded":False},s["token"])
        job=result.get("Job",result);s["job"]=str(job["Id"]);created_jobs.append(s["job"])
    deadline=time.monotonic()+20
    while True:
        for owner,s in states.items():
            items=call("Sync/JobItems?JobId="+s["job"],token=s["token"])
            a=items.get("Items",[]) if isinstance(items,dict) else items
            if a:s["jobitem"]=str(a[0]["Id"]);s["status"]=a[0].get("Status")
        if all(s.get("status")=="ReadyToTransfer" for s in states.values()):break
        if time.monotonic()>deadline:break
        time.sleep(.5)
    for owner,s in states.items():
        other=states["b" if owner=="a" else "a"]
        record("Native prepared file state "+owner,Status=s.get("status"),HasJobItem="jobitem" in s)
        if "jobitem" not in s:continue
        for actor,token in (("owner",s["token"]),("other user",other["token"])):
            status,data=request("Sync/JobItems/"+s["jobitem"]+"/File",token=token,binary=True)
            record("Real Sync file "+owner+" requested by "+actor,HttpStatus=status,Bytes=len(data),Mp4=b"ftyp" in data[:32],SourceMatch=data==base64.b64decode(SAMPLE))
except Exception as e:
    record("Failure",Error=str(e))
finally:
    failures=[]
    for jid in created_jobs:
        try:call("Sync/Jobs/"+jid,"DELETE")
        except Exception as e:failures.append("job: "+str(e))
    for lid in created_libs:
        try:call("Library/VirtualFolders/Delete","POST",{"Id":lid})
        except Exception as e:failures.append("library: "+str(e))
    for uid in created_users:
        try:call("Users/"+uid,"DELETE")
        except Exception as e:failures.append("user: "+str(e))
    for device in devices:
        try:call("Devices?Id="+device,"DELETE")
        except Exception as e:failures.append("device: "+str(e))
    if root.exists() and root.parent.resolve()==CONFIG.resolve() and root.name==stamp:shutil.rmtree(root)
    try:
        remaining_users={x["Id"] for x in call("Users")}
        remaining_libs={x["ItemId"] for x in call("Library/VirtualFolders/Query")["Items"]}
        jobs=call("Sync/Jobs");remaining_jobs={str(x["Id"]) for x in jobs.get("Items",[])}
        record("Cleanup readback",UsersGone=not remaining_users.intersection(created_users),LibrariesGone=not remaining_libs.intersection(created_libs),JobsGone=not remaining_jobs.intersection(created_jobs),MediaFolderGone=not root.exists(),Errors=failures)
    except Exception as e:record("Cleanup readback failure",Error=str(e),Errors=failures)
    print(json.dumps({"PrototypeInstalled":False,"Observations":observations}))

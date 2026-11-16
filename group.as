class Participant {
    string id,name,piece,replay,readyHash;
    bool placed=false,applied=false,ready=false,replayReady=false,done=false,revealed=false,skip=false;
}
array<Participant@> players;
string pendingMap;
int Index(const string &in id) { for(uint i=0;i<players.length();i++) if(players[i].id==id) return int(i);return -1; }
Participant@ Me() {int i=Index(Together::OwnId());return i<0?null:players[i];}
bool All(int flag) {
    if(players.length()<2 || players.length()>4) return false;
    for(uint i=0;i<players.length();i++) {
        Participant@ p=players[i];
        if(flag==0 && (!p.placed || !p.applied)) return false;
        if(flag==1 && (!p.ready || p.readyHash!=mapHash)) return false;
        if(flag==2 && p.replay=="") return false;
        if(flag==3 && !p.replayReady) return false;
        if(flag==4 && !p.done) return false;
        if(flag==5 && !p.skip) return false;
    }
    return true;
}
string Roster() {string value="";for(uint i=0;i<players.length();i++) value+=(i==0?"":",")+players[i].id;return value;}
void SyncParticipants() {
    array<string>@ ids=Together::LobbyMemberIds();array<string>@ names=Together::LobbyMembers();
    array<string> sorted=ids;sorted.sortAsc();
    string host=Together::LobbyOwnerId();int at=sorted.find(host);
    if(at>=0) {sorted.removeAt(at);sorted.insertAt(0,host);}
    string expected="";for(uint i=0;i<sorted.length();i++) expected+=(i==0?"":",")+sorted[i];
    if(sessionActive) {
        if(expected!=Roster() || host!=ownerId) {if(leftSince<0) leftSince=Host::Time();if(Host::Time()-leftSince>2) Abort("A participant left or the host changed. Start a new party.");}
        else leftSince=-1;
        return;
    }
    if(expected==Roster()) return;
    players.resize(0);
    for(uint i=0;i<sorted.length();i++) {
        Participant@ p=Participant();p.id=sorted[i];int j=ids.find(p.id);p.name=j>=0 && uint(j)<names.length()?names[j]:"Player";players.insertLast(p);
    }
    array<PartyLink@> current;
    for(uint i=0;i<players.length();i++) if(players[i].id!=Together::OwnId()) {
        PartyLink@ link=Link(players[i].id);if(link is null) {@link=PartyLink();link.id=players[i].id;}
        current.insertLast(link);
    }
    links=current;
}
bool Compatible() {
    if(players.length()<2 || players.length()>4) return false;
    for(uint i=0;i<links.length();i++) if(links[i].version!=VERSION || Host::Time()-links[i].seen>15) return false;
    return links.length()+1==players.length();
}
void GroupNewRound() {
    pendingMap="";
    for(uint i=0;i<players.length();i++) {
        Participant@ p=players[i];p.piece="";p.replay="";p.readyHash="";
        p.placed=false;p.applied=false;p.ready=false;p.replayReady=false;p.done=false;p.revealed=false;p.skip=false;
    }
}
void GroupSubmit() {
    if(phase!=BUILD || ownPlaced || Me() is null) return;
    if(selected<0) {selected=0;if(PartyStage::Choose(0)==0) {NativeFail("Object selection");return;}}
    string item=PartyStage::Capture();if(item=="") {Notice(PartyStage::Error());return;}
    if(!PartyStage::Append(item,true)) {NativeFail("Saving your object");return;}
    Participant@ p=Me();p.piece=item;p.placed=true;p.applied=true;ownPlaced=true;SendBlob("P",item);
    Log::Info("PARTY committed participant="+p.id+" round="+roundNumber);
}
void GroupBlob(const string &in from,const string &in kind,const string &in text) {
    if(phase==STOPPED) return;
    int at=Index(from);if(at<0 || !sessionActive) {Abort("Unknown party participant.");return;}
    Participant@ p=players[at];
    if(kind=="P") {
        if((phase!=BUILD && phase!=BUILD_LOADING) || p.placed) {Abort("Duplicate or late object.");return;}
        p.piece=text;p.placed=true;return;
    }
    if(kind=="M") {
        if(from!=ownerId || Hosting() || (phase!=BUILD && phase!=BUILD_LOADING) || pendingMap!="") {Abort("Unexpected authoritative track.");return;}
        pendingMap=text;return;
    }
    if(kind=="R") {
        if((phase!=RACING && phase!=COUNTDOWN && phase!=RACE_LOADING && phase!=REPLAY_LOADING) || p.replay!="") {Abort("Duplicate or late recording.");return;}
        p.replay=text;return;
    }
    Abort("Unknown party payload.");
}
void GroupControl(const string &in from,array<string>@ p) {
    if(p.length()==0 || phase==STOPPED) return;
    if(p[0]=="START") {
        if(from!=Together::LobbyOwnerId() || Hosting() || sessionActive || !Compatible() || p.length()!=6 || p[3]!=Roster() || p[4].length()>3 || p[4].findFirstNotOf("0123456789")>=0 || parseInt(p[4])<1 || parseInt(p[4])>100 || p[2].length()>3 || p[2].findFirstNotOf("0123456789")>=0 || parseInt(p[2])<1 || parseInt(p[2])>600 || p[5].length()>3 || p[5].findFirstNotOf("0123456789")>=0 || parseInt(p[5])<10 || parseInt(p[5])>600) {Abort("Invalid party start or roster.");return;}
        raceSeconds=parseInt(p[2]);roundLimit=parseInt(p[4]);buildSeconds=parseInt(p[5]);Begin(p[1]);return;
    }
    int at=Index(from);
    if(at<0 || !sessionActive || p.length()<3 || p[1]!=session || parseInt(p[2])!=roundNumber) {Abort("Party message belongs to another round.");return;}
    Participant@ sender=players[at];
    if(p[0]=="READY" && p.length()==4 && (phase==BUILD || phase==RACE_LOADING || phase==COUNTDOWN || phase==RACING)) {sender.ready=true;sender.readyHash=p[3];return;}
    if(p[0]=="GO" && p.length()==3 && from==ownerId && !Hosting() && phase==RACE_LOADING && Me().ready) {countdownAt=Host::Time()+10;Phase(COUNTDOWN);return;}
    if(p[0]=="REPLAY_READY" && p.length()==3 && (phase==RACING || phase==REPLAY_LOADING || phase==WATCHING)) {sender.replayReady=true;return;}
    if(p[0]=="WATCH" && p.length()==3 && from==ownerId && !Hosting() && phase==REPLAY_LOADING && Me().replayReady) {
        if(!PartyStage::StartReplay()) NativeFail("Starting replay");else Phase(WATCHING);return;
    }
    if(p[0]=="DONE" && p.length()==3 && (phase==WATCHING || phase==REPLAY_LOADING)) {sender.done=true;return;}
    if(p[0]=="SKIP" && p.length()==3 && phase==WATCHING) {sender.skip=true;return;}
    if(p[0]=="NEXT" && p.length()==4 && from==ownerId && !Hosting() && phase==WATCHING && ownDone && parseInt(p[3])==roundNumber+1) {nextRoundQueued=true;return;}
    Abort("Unexpected party phase message.");
}
void GroupOpenRace() {
    string snapshot=PartyStage::Snapshot();mapHash=PartyStage::Digest(snapshot);SendBlob("M",snapshot);
    if(!PartyStage::OpenRace(roundNumber)) {NativeFail("Loading race");return;}
    Phase(RACE_LOADING);
}
void AdvanceParty()
{
    if(roundNumber>=roundLimit) {Phase(PARTY_DONE);window.visible=true;Log::Info("PARTY configured rounds complete="+roundLimit);}
    else NewRound(roundNumber+1);
}
void GroupRound() {
    double now=Host::Time();
    if(phase==BUILD_LOADING) {
        if(PartyStage::BuildReady()) {
            array<string>@ offered=PartyStage::Offers();array<string>@ icons=PartyStage::OfferIcons();
            for(uint i=0;i<3 && i<offered.length();i++) choices[i].label=offered[i];
            for(uint i=0;i<3 && i<icons.length();i++) choiceIcons[i].path=icons[i];
            if(offered.length()==3) Log::Info("PARTY offers="+offered[0]+"|"+offered[1]+"|"+offered[2]);
            buildDeadline=now+buildSeconds;Phase(BUILD);
        } else if(now-phaseSince>60) NativeFail("Loading build phase");
    }
    if(phase==BUILD) {
        for(uint i=0;i<players.length();i++) if(players[i].placed && !players[i].applied) {
            if(!PartyStage::Append(players[i].piece)) {NativeFail("Shared object");return;}players[i].applied=true;
        }
        if(!ownPlaced && now>=buildDeadline) {GroupSubmit();if(!ownPlaced) {NativeFail("Object placement deadline");return;}}
        if(Hosting() && All(0) && TransportIdle()) GroupOpenRace();
        else if(!Hosting() && All(0) && pendingMap!="") {
            if(!PartyStage::SetSnapshot(pendingMap)) {NativeFail("Shared track");return;}
            mapHash=PartyStage::Digest(pendingMap);pendingMap="";
            if(!PartyStage::OpenRace(roundNumber)) {NativeFail("Loading race");return;}Phase(RACE_LOADING);
        }
        else if(now-phaseSince>buildSeconds+60) Abort("Not all participants placed their objects.");
    }
    if(phase==RACE_LOADING) {
        if(!Me().ready && PartyStage::RaceReady()) {Me().ready=true;Me().readyHash=mapHash;Enqueue("READY|"+session+"|"+roundNumber+"|"+mapHash);}
        if(Hosting() && All(1) && TransportIdle()) {Enqueue("GO|"+session+"|"+roundNumber);countdownAt=now+10;Phase(COUNTDOWN);}
        else if(now-phaseSince>120) Abort("Not all participants loaded the same track.");
    }
    if(phase==COUNTDOWN && (Race::IsActive() || now>=countdownAt)) {
        if(!PartyStage::StartRace()) {NativeFail("Starting race");return;}
        raceRestarts=Race::Restarts();inactiveSince=-1;Phase(RACING);window.visible=false;
    }
    if(phase==RACING) {
        if(ownReplay=="") {
            string recording=PartyStage::FinishedReplay();
            if(recording!="") {
                ownReplay=recording;Me().replay=recording;ownTimedOut=!Json::Bool(recording,"?PartyFinished",true);
                if(ownTimedOut) result.text="DNF - Time limit reached.";
                window.visible=true;lastUi=-100;SendBlob("R",recording);
            }
            else if(Race::Restarts()!=raceRestarts) {Abort("The race restarted outside Party Mode.");return;}
            else if(now-phaseSince>raceSeconds+20) {Abort("The recording was not available after the deadline.");return;}
        }
        if(All(2)) {
            array<string> ids,recordings;
            for(uint i=0;i<players.length();i++) {ids.insertLast(players[i].id);recordings.insertLast(players[i].replay);}
            if(!PartyStage::PrepareReplayGroup(ids,recordings)) {NativeFail("Preparing participant replays");return;}
            Phase(REPLAY_LOADING);
        } else if(now-phaseSince>raceSeconds+180) Abort("Not all participant recordings arrived.");
    }
    if(phase==REPLAY_LOADING) {
        if(!Me().replayReady && PartyStage::ReplayReady()) {Me().replayReady=true;Enqueue("REPLAY_READY|"+session+"|"+roundNumber);}
        if(Hosting() && All(3) && TransportIdle()) {
            Enqueue("WATCH|"+session+"|"+roundNumber);if(!PartyStage::StartReplay()) {NativeFail("Starting replay");return;}Phase(WATCHING);
        } else if(now-phaseSince>120) Abort("Not all participant ghosts loaded.");
    }
    if(phase==WATCHING) {
        double clock=PartyStage::ReplayClock(),lastFinish=0;string shown="";
        for(uint i=0;i<players.length();i++) {
            bool finished=PartyStage::ReplayFinished(int(i));double time=PartyStage::FinishTime(int(i));
            if(finished) lastFinish=Max(lastFinish,time);
            if(forceReplayReveal || !finished || clock>=time) {
                int rank=1;bool tie=false;
                for(uint j=0;j<players.length();j++) if(j!=i && PartyStage::ReplayFinished(int(j))) {
                    double other=PartyStage::FinishTime(int(j));if(other<time-0.0005) rank++;else if(Math::abs(other-time)<0.0005) tie=true;
                }
                string place=rank==1?"1st":rank==2?"2nd":rank==3?"3rd":"4th";
                shown+=players[i].name+(finished?" - "+place+"  "+formatFloat(time,"",0,3)+" s"+(tie?" (tie)":""):" - DNF (time limit)")+"\n";
                if(!players[i].revealed) {players[i].revealed=true;Log::Info("PARTY reveal participant="+players[i].id+" playback="+clock+" finish="+time+" reachedGoal="+finished);}
            }
        }
        result.text=shown;
        if(!ownDone && (forceReplayReveal || All(5) || clock>=lastFinish)) {
            forceReplayReveal=forceReplayReveal || All(5);
            if(!PartyStage::HoldReplay()) {NativeFail("Holding results");return;}
            ownDone=true;Me().done=true;phaseSince=now;lastUi=-100;Enqueue("DONE|"+session+"|"+roundNumber);
            Log::Info("PARTY results hold started; lastFinish="+lastFinish+" seconds=5");
        }
        if(Hosting() && All(4) && now-phaseSince>=RESULTS_HOLD_SECONDS && TransportIdle()) {Enqueue("NEXT|"+session+"|"+roundNumber+"|"+(roundNumber+1));AdvanceParty();}
        else if(!Hosting() && ownDone && nextRoundQueued && now-phaseSince>=RESULTS_HOLD_SECONDS) AdvanceParty();
        else if(clock<0 && now-phaseSince>10 && !ownDone) Abort("The replay stopped unexpectedly.");
        else if(ownDone && now-phaseSince>120) Abort("Not all participants completed the replay.");
    }
}
void GroupUpdate() {
    if(create.Clicked()) {noticeUntil=0;ResetTransport();players.resize(0);Together::CreateLobby(Together::Friends,4);}
    if(invite.Clicked() && !Together::InviteDialog()) Notice("Steam invite unavailable. Share the invite code.");
    if(copyCode.Clicked()) Host::SetClipboard("BPM1:"+Together::LobbyId());
    if(joinButton.Clicked() || code.Submitted()) JoinCode();
    string invitation=Together::TakeInvite();if(invitation!="" && !sessionActive) Together::JoinLobby(invitation);
    string current=Together::LobbyState()=="in lobby"?Together::LobbyId():"";
    if(current!=lobbyId) {
        if(sessionActive) {Abort("The party lobby closed.");return;}
        lobbyId=current;ResetTransport();players.resize(0);lastHello=-100;
        if(current!="" && Hosting()) {Together::SetLobbyData("ballest_party",VERSION);Together::SetLobbyData("party_race_seconds",""+raceSeconds);Together::SetLobbyData("party_rounds",""+roundLimit);Together::SetLobbyData("party_build_seconds",""+buildSeconds);}
    }
    SyncParticipants();if(phase==STOPPED) return;
    if(current!="" && !Hosting() && !sessionActive) {
        string count=Together::LobbyData("party_rounds");
        if(count.length()>0 && count.length()<=3 && count.findFirstNotOf("0123456789")<0 && parseInt(count)>=1 && parseInt(count)<=100) roundLimit=parseInt(count);
        string shared=Together::LobbyData("party_race_seconds");if(shared.length()>0 && shared.length()<=3 && shared.findFirstNotOf("0123456789")<0 && parseInt(shared)>=1 && parseInt(shared)<=600) raceSeconds=parseInt(shared);
        string build=Together::LobbyData("party_build_seconds");if(build.length()>0 && build.length()<=3 && build.findFirstNotOf("0123456789")<0 && parseInt(build)>=10 && parseInt(build)<=600) buildSeconds=parseInt(build);
    }
    if(current!="" && Host::Time()-lastHello>3) {Together::SendPluginMessage("H7|"+VERSION);lastHello=Host::Time();}
    ReceiveTransport();
    if(start.Clicked()) {
        if(!Hosting() || !Compatible()) Notice("A party needs 2–4 players with the same plugin version.");
        else {noticeUntil=0;string token=PartyStage::Digest(Together::LobbyId()+"|"+Host::Time()).substr(0,24);Enqueue("START|"+token+"|"+raceSeconds+"|"+Roster()+"|"+roundLimit+"|"+buildSeconds);Begin(token);}
    }
    if(phase==BUILD && !ownPlaced) {
        for(uint i=0;i<3;i++) if(choices[i].Clicked() && selected<0) {if(PartyStage::Choose(i)==0) NativeFail("Object selection");else selected=int(i);}
        if(commit.Clicked()) GroupSubmit();
    }
    if(sessionActive && phase!=STOPPED) GroupRound();
    PumpTransport();if(Host::Time()-lastUi>0.2) {lastUi=Host::Time();Refresh();}
}

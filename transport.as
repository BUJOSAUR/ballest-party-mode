// Reliable addressed streams over the Manager's authenticated lobby messages.
// Each remote participant has independent sequencing, acknowledgements and blob state.
class PartyLink {
    string id, version, kind, hash, blob;
    int length=0, tx=1, rx=1;
    double seen=-100, sent=-100, outstanding=-1;
    array<string> queue;
}
array<PartyLink@> links;
array<string> sendQueue; // Private legacy Solo does not use the network.
PartyLink@ Link(const string &in id) {
    for(uint i=0;i<links.length();i++) if(links[i].id==id) return links[i];
    return null;
}
void ResetTransport() { links.resize(0); sendQueue.resize(0); }
bool TransportIdle() {
    for(uint i=0;i<links.length();i++) if(links[i].queue.length()>0) return false;
    return true;
}
void Enqueue(const string &in message) {
    for(uint i=0;i<links.length();i++) {
        if(links[i].queue.length()>=16000 || message.length()>640) {Abort("Party message queue is full.");return;}
        links[i].queue.insertLast(message);
    }
}
void SendBlob(const string &in kind,const string &in text) {
    string packed=PartyStage::Pack(text);
    if(packed=="" || packed.length()>1500000) {Abort("Party recording is too large.");return;}
    Enqueue("B|"+session+"|"+roundNumber+"|"+kind+"|"+packed.length()+"|"+PartyStage::Digest(text));
    for(uint offset=0;offset<packed.length();offset+=512) Enqueue("C|"+offset+"|"+packed.substr(offset,512));
    Enqueue("E");
}
void Logical(PartyLink@ link,const string &in message) {
    array<string>@ p=message.split("|");
    if(p[0]=="B") {
        if(p.length()!=6 || p[1]!=session || parseInt(p[2])!=roundNumber || link.kind!="" || (p[3]!="P" && p[3]!="M" && p[3]!="R") || p[4].findFirstNotOf("0123456789")>=0 || p[4].length()>7 || parseInt(p[4])<1 || parseInt(p[4])>1500000 || p[5].length()!=64) {Abort("Invalid party transfer.");return;}
        link.kind=p[3];link.length=parseInt(p[4]);link.hash=p[5];link.blob="";return;
    }
    if(p[0]=="C") {
        if(p.length()!=3 || link.kind=="" || parseInt(p[1])!=int(link.blob.length()) || link.blob.length()+p[2].length()>uint(link.length)) {Abort("Party data arrived out of order.");return;}
        link.blob+=p[2];return;
    }
    if(p[0]=="E") {
        if(p.length()!=1 || link.kind=="" || link.blob.length()!=uint(link.length)) {Abort("Incomplete party data.");return;}
        string raw=PartyStage::Unpack(link.blob),kind=link.kind;link.kind="";link.blob="";
        if(raw=="" || PartyStage::Digest(raw)!=link.hash) {Abort("Party data could not be verified.");return;}
        GroupBlob(link.id,kind,raw);return;
    }
    GroupControl(link.id,p);
}
void ReceiveTransport() {
    string from,message;
    while(Together::NextPluginMessage(from,message)) {
        PartyLink@ link=Link(from);if(link is null || from==Together::OwnId()) continue;
        array<string>@ p=message.split("|");
        if(p.length()==2 && p[0]=="H7") {link.version=p[1];link.seen=Host::Time();continue;}
        if(p.length()<3 || p[1]!=Together::OwnId()) continue;
        if(p[0]=="A7" && p.length()==3) {
            if(link.queue.length()>0 && parseInt(p[2])==link.tx) {link.queue.removeAt(0);link.tx++;link.sent=-100;link.outstanding=-1;}
            continue;
        }
        if(p[0]!="D7" || p.length()<4 || phase==STOPPED) continue;
        int sequence=parseInt(p[2]);if(sequence<1 || sequence>link.rx) continue;
        Together::SendPluginMessage("A7|"+from+"|"+sequence);
        if(sequence!=link.rx) continue;
        link.rx++;uint offset=message.findFirst("|",message.findFirst("|",3)+1);
        Logical(link,message.substr(offset+1));
    }
}
void PumpTransport() {
    double now=Host::Time();
    for(uint i=0;i<links.length();i++) {
        PartyLink@ link=links[i];if(link.queue.length()==0) continue;
        if(link.outstanding>=0 && now-link.outstanding>90) {Abort("A participant stopped responding.");return;}
        if(now-link.sent<0.1) continue;
        if(Together::SendPluginMessage("D7|"+link.id+"|"+link.tx+"|"+link.queue[0])) {link.sent=now;if(link.outstanding<0) link.outstanding=now;}
    }
}

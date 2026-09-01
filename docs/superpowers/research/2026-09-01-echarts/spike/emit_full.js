const fs=require('fs');
const en=JSON.parse(fs.readFileSync(process.argv[2],'utf-8'));
const zh=JSON.parse(fs.readFileSync(process.argv[3],'utf-8'));
function strip(h){return (h||'').replace(/<iframe[\s\S]*?<\/iframe>/g,'').replace(/<[^>]+>/g,'')
  .replace(/&#39;/g,"'").replace(/&quot;/g,'"').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>')
  .replace(/[ \t]+/g,' ').replace(/\n{2,}/g,'\n').trim();}
function firstPara(t){ const i=t.indexOf('\n'); return t; }
// intern tables
const strs=new Map(); const strList=[];
function S(x){ if(x==null)x=''; if(!strs.has(x)){strs.set(x,strList.length); strList.push(x);} return strs.get(x); }
S(''); // 0
// shape dedup
const shapes=new Map(); const nodes=[]; // {nameIdx,typeIdx,defIdx,enumIdx,uiIdx,descEnIdx,descZhIdx,firstChild,childCount}
const enums=new Map(); const enumList=[];
function E(x){ if(!x) return -1; if(!enums.has(x)){enums.set(x,enumList.length); enumList.push(x);} return enums.get(x); }
function build(nEn,nZh,name){
  const childrenEn = nEn.items ? (nEn.items.anyOf? null : nEn.items.properties) : nEn.properties;
  const anyOf = nEn.items && nEn.items.anyOf;
  const kids=[];
  if(anyOf){
    anyOf.forEach((c,i)=>{ const z=(nZh&&nZh.items&&nZh.items.anyOf)?nZh.items.anyOf[i]:null;
      const tn=c.properties&&c.properties.type&&c.properties.type.default; kids.push(build(c,z,String(tn||i).replace(/'/g,''))); });
  } else if(childrenEn){
    const zc = nZh ? (nZh.items? (nZh.items.properties||{}) : (nZh.properties||{})) : {};
    for(const k of Object.keys(childrenEn)) kids.push(build(childrenEn[k], zc[k], k));
  }
  const dEn=strip(nEn.description), dZh=strip(nZh&&nZh.description);
  const ver=(nEn.description||'').match(/doc-partial-version.{0,60}?v([0-9][0-9.a-zA-Z]*)/s);
  const rec={
    n:name,
    t:Array.isArray(nEn.type)?nEn.type.join('|'):String(nEn.type||''),
    d:nEn.default==null?'':String(nEn.default),
    ui:nEn.uiControl?nEn.uiControl.type:'',
    en:E(nEn.uiControl&&nEn.uiControl.options),
    ver:ver?ver[1]:'',
    de:firstPara(dEn), dz:firstPara(dZh),
    kids
  };
  const sig=JSON.stringify([rec.n,rec.t,rec.d,rec.ui,rec.en,rec.ver,rec.de,rec.dz,kids]);
  if(shapes.has(sig)) return shapes.get(sig);
  const idx=nodes.length; nodes.push(rec); shapes.set(sig,idx); return idx;
}
const root=build(en.option, zh.option, 'option');
console.log('emitted nodes:',nodes.length,'root idx',root,'distinct enums:',enumList.length);
// flatten children into one array
const childArr=[];
nodes.forEach(r=>{ r.first=childArr.length; r.count=r.kids.length; r.kids.forEach(k=>childArr.push(k)); });
function q(s){var parts=String(s).replace(/'/g,"''").replace(/\r/g,"").split("\n"); return parts.map(function(x){return "'"+x+"'";}).join("+#10+");}
let out=[];
out.push('unit TyEChartsCatalogFull;');
out.push('{$mode objfpc}{$H+}');
out.push('interface');
out.push('type');
out.push('  TTyOptNode = record');
out.push('    Name, Kind, DefVal, UiKind, SinceVer: string;');
out.push('    EnumIdx, FirstChild, ChildCount: Integer;');
out.push('    DescEn, DescZh: string;');
out.push('  end;');
out.push('const');
out.push('  TyOptRoot = '+root+';');
out.push('  TyOptEnums: array[0..'+(enumList.length-1)+'] of string = (');
out.push(enumList.map(e=>'    '+q(e)).join(',\n')+');');
out.push('  TyOptChildren: array[0..'+(childArr.length-1)+'] of Integer = (');
out.push('    '+childArr.join(', ')+');');
out.push('  TyOptNodes: array[0..'+(nodes.length-1)+'] of TTyOptNode = (');
out.push(nodes.map(r=>'    (Name:'+q(r.n)+'; Kind:'+q(r.t)+'; DefVal:'+q(r.d)+'; UiKind:'+q(r.ui)+'; SinceVer:'+q(r.ver)+
  '; EnumIdx:'+r.en+'; FirstChild:'+r.first+'; ChildCount:'+r.count+'; DescEn:'+q(r.de)+'; DescZh:'+q(r.dz)+')').join(',\n')+');');
out.push('implementation');
out.push('end.');
const txt=out.join('\n');
fs.writeFileSync(process.argv[4],txt,'utf-8');
console.log('unit bytes:',Buffer.byteLength(txt,'utf8'),'lines:',txt.split('\n').length);
console.log('children array length:',childArr.length);

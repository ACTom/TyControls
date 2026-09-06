const fs=require('fs'),path=require('path');
const dir='D:/Projects/echarts/test';
const files=fs.readdirSync(dir).filter(f=>f.endsWith('.html'));
let out=[], stats={files:0,found:0};
for(const f of files){
  const t=fs.readFileSync(path.join(dir,f),'utf-8');
  stats.files++;
  const re=/\boption\s*=\s*\{/g; let m;
  while((m=re.exec(t))){
    let i=m.index+m[0].length-1, depth=0, j=i, inStr=null, esc=false;
    for(;j<t.length;j++){const c=t[j];
      if(inStr){ if(esc){esc=false;continue;} if(c===String.fromCharCode(92)){esc=true;continue;} if(c===inStr)inStr=null; continue;}
      if(c==='"'||c==="'"||c==='`'){inStr=c;continue;}
      if(c==='{')depth++; else if(c==='}'){depth--; if(depth===0){j++;break;}}
    }
    if(depth===0 && j>i){ out.push({file:f, code:t.slice(i,j)}); stats.found++; }
    re.lastIndex=j;
  }
}
console.log(JSON.stringify(stats));
fs.writeFileSync(process.argv[2], out.map(o=>o.file+'\u0001'+o.code.replace(/\r?\n/g,'\u0002')).join('\n'),'utf-8');
// quick JS-side classification
let fn=0, tmpl=0, varRef=0, spread=0;
for(const o of out){ if(/function\s*\(|=>/.test(o.code))fn++; if(/`/.test(o.code))tmpl++; if(/\.\.\./.test(o.code))spread++; }
console.log('extracted option literals:',out.length,' with function:',fn,' with template literal:',tmpl,' with spread:',spread);

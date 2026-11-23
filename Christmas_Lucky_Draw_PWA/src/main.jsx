import React, {useEffect, useMemo, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {createClient} from '@supabase/supabase-js';
import {Gift, Snowflake, Users, LockKeyhole, Sparkles, Copy, LogOut, RotateCcw} from 'lucide-react';
import './style.css';

const URL = import.meta.env.VITE_SUPABASE_URL;
const KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabase = URL && KEY ? createClient(URL, KEY) : null;
const localIdKey = 'christmas_draw_participant_id';
const getPid = () => { let v=localStorage.getItem(localIdKey); if(!v){v=crypto.randomUUID();localStorage.setItem(localIdKey,v)} return v; };

function App(){
 const [count,setCount]=useState(25), [name,setName]=useState(''), [pid]=useState(getPid), [limitInput,setLimitInput]=useState(25);
 const [participant,setParticipant]=useState(null), [gifts,setGifts]=useState([]), [total,setTotal]=useState(0);
 const [adminOpen,setAdminOpen]=useState(false), [password,setPassword]=useState(''), [adminOk,setAdminOk]=useState(false);
 const [giftEdits,setGiftEdits]=useState({}), [busy,setBusy]=useState(false), [notice,setNotice]=useState('');
 const [configured,setConfigured]=useState(Boolean(supabase));
 const [resetPassword,setResetPassword]=useState('');

 async function load(){
  if(!supabase){setConfigured(false);return}
  const {data,error}=await supabase.rpc('public_event');
  if(error){setNotice('雲端尚未完成設定：請依照 SETUP.md 建立資料庫。');return}
  setConfigured(true); setCount(data?.participant_limit||25); setLimitInput(data?.participant_limit||25);
  const {data:mine}=await supabase.rpc('my_draw',{p_participant_id:pid});
  setParticipant(mine?.[0]||null);
  const {data:list}=await supabase.rpc('public_gifts');
  setGifts(list||[]);
  setTotal((list||[]).filter(x=>x.participant_name).length);
 }
 useEffect(()=>{load(); if(!supabase)return; const poll=setInterval(load,5000); const ch=supabase.channel('draw-live').on('postgres_changes',{event:'*',schema:'public',table:'gift_numbers'},()=>load()).on('postgres_changes',{event:'*',schema:'public',table:'participants'},()=>load()).subscribe(); return()=>{clearInterval(poll);supabase.removeChannel(ch)}},[]);
 async function draw(e){e.preventDefault(); if(!name.trim())return setNotice('請輸入姓名'); setBusy(true);setNotice(''); const {data,error}=await supabase.rpc('draw_number',{p_name:name.trim(),p_participant_id:pid}); if(error)setNotice(error.message);else{setParticipant(data);setNotice('抽籤成功！請記住你的號碼。'); await load()} setBusy(false)}
 async function login(){setBusy(true);const {data,error}=await supabase.rpc('admin_check',{p_password:password}); if(error||!data){setNotice('管理員密碼錯誤');setAdminOk(false)}else{setAdminOk(true);setNotice('管理員驗證成功')}setBusy(false)}
 async function saveLimit(){const v=Number(limitInput);if(!Number.isInteger(v)||v<1||v>25){setNotice('人數必須介於 1 到 25 人');return}setBusy(true);const {error}=await supabase.rpc('admin_set_limit',{p_password:password,p_limit:v});setNotice(error?error.message:`抽籤人數已設定為 ${v} 人`);if(!error)await load();setBusy(false)}
 async function saveGift(n){setBusy(true);const {error}=await supabase.rpc('admin_set_gift',{p_password:password,p_number:n,p_gift:(giftEdits[n]??gifts.find(g=>g.number===n)?.gift_name??'').trim()});setNotice(error?error.message:`${n} 號禮物已更新`);if(!error)await load();setBusy(false)}
 async function resetAll(){
  if(!resetPassword){setNotice('請再次輸入管理員密碼確認重置');return}
  if(!window.confirm('確定要全部 Reset 嗎？這會清除所有參加者、抽籤紀錄及禮物名稱，且無法復原。'))return;
  setBusy(true);setNotice('');
  const {error}=await supabase.rpc('admin_reset_event',{p_password:resetPassword});
  if(error){setNotice(error.message);setBusy(false);return}
  setName('');setParticipant(null);setGiftEdits({});setResetPassword('');
  await load();
  setNotice('全部 Reset 完成：參加者、抽籤紀錄及禮物名稱已清空；人數設定與管理員密碼保留。');
  setBusy(false);
 }
 async function copyLink(){await navigator.clipboard.writeText(location.href);setNotice('活動連結已複製')}
 const sorted=useMemo(()=>[...gifts].sort((a,b)=>a.number-b.number),[gifts]);
 return <main className="shell"><header><div className="snow"><Snowflake/><Snowflake/><Snowflake/></div><div className="brand">CHRISTMAS <span>✦</span> 2026</div><h1>聖誕幸運抽籤</h1><p>Share the joy · Find your lucky gift</p><div className="ornament">🎄　🎁　❄️　🎅　❄️　🎁</div></header>
 <section className="stats"><div><Users/><b>{count}</b><small>抽籤名額</small></div><div><Gift/><b>{total}</b><small>已抽出人數</small></div><div><Sparkles/><b>{Math.max(0,count-total)}</b><small>剩餘名額</small></div></section>
 {!configured?<section className="panel"><h2>雲端服務尚未設定</h2><p>請先依照專案內的 SETUP.md 設定 Supabase，再填入部署環境變數，完成後即可多人同步抽籤。</p></section>:<>
 {!participant?<form className="panel" onSubmit={draw}><div className="section-title"><Gift/><h2>抽出你的聖誕號碼</h2></div><label>你的姓名</label><input value={name} onChange={e=>setName(e.target.value)} maxLength="40" placeholder="請輸入姓名" required/><button disabled={busy||total>=count} className="primary">{busy?'抽籤中…':'🎁 開始抽籤'}</button><p className="hint">每位參加者限抽一次，抽出後號碼即固定。</p></form>:<section className="panel result"><div>YOUR LUCKY NUMBER</div><div className="big-number">{String(participant.number).padStart(2,'0')}</div><h2>恭喜 {participant.name}！</h2><p>請記住你的號碼，並到下方查看禮物清單。</p></section>}
 <section className="panel"><div className="section-title"><Gift/><h2>公開禮物清單</h2><span className="live">LIVE</span></div><p className="hint">所有參加者都能查看，管理員更新後會同步顯示。</p><div className="gift-grid">{sorted.map(g=><article className="gift-card" key={g.number}><div className="number">{String(g.number).padStart(2,'0')} 號</div><div className="gift-name">{g.gift_name||'🎁 神秘禮物'}</div>{g.participant_name&&<small>已抽出</small>}</article>)}</div></section>
 </>}
 <footer><button className="ghost" onClick={copyLink}><Copy size={16}/> 複製活動連結</button><button className="ghost" onClick={()=>{setAdminOpen(!adminOpen);setAdminOk(false)}}><LockKeyhole size={16}/> 管理員</button></footer>
 {adminOpen&&<section className="panel admin"><div className="section-title"><LockKeyhole/><h2>管理員後台</h2></div>{!adminOk?<><label>管理員密碼</label><input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="輸入管理員密碼"/><button className="primary" onClick={login} disabled={busy}>登入管理員</button></>:<>
 <p className="hint">設定參加人數（1–25 人），再編輯號碼對應的禮物。</p>
 <div className="limit-row"><label>參加人數</label><input type="number" min="1" max="25" value={limitInput} onChange={e=>setLimitInput(e.target.value)}/><button onClick={saveLimit} disabled={busy}>更新人數</button></div>
 {sorted.slice(0,count).map(g=><div className="edit-row" key={g.number}><b>{String(g.number).padStart(2,'0')} 號</b><input value={giftEdits[g.number]??g.gift_name??''} onChange={e=>setGiftEdits({...giftEdits,[g.number]:e.target.value})} placeholder="輸入禮物名稱"/><button onClick={()=>saveGift(g.number)} disabled={busy}>儲存</button></div>)}
 <div className="reset-box"><div className="section-title"><RotateCcw/><h3>全部 Reset</h3></div><p className="hint">清除所有參加者、抽籤紀錄及禮物名稱。抽籤名額與管理員密碼會保留，此操作無法復原。</p><label>再次輸入管理員密碼</label><input type="password" value={resetPassword} onChange={e=>setResetPassword(e.target.value)} placeholder="輸入管理員密碼以確認 Reset"/><button className="danger" onClick={resetAll} disabled={busy}>{busy?'處理中…':'全部 Reset'}</button></div>
 <button className="ghost" onClick={()=>{setAdminOk(false);setPassword('');setResetPassword('')}}><LogOut size={16}/> 登出</button>
 </>}</section>}
 {notice&&<div className="notice" role="status">{notice}<button onClick={()=>setNotice('')}>×</button></div>}
 <p className="fine">Made with 🎄 for a joyful Christmas</p></main>
}
createRoot(document.getElementById('root')).render(<App/>);

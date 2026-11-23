import React, {useEffect, useMemo, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {createClient} from '@supabase/supabase-js';
import {Gift,Snowflake,Users,LockKeyhole,Sparkles,Copy,LogOut,RotateCcw,CheckCircle2} from 'lucide-react';
import './style.css';

const URL=import.meta.env.VITE_SUPABASE_URL;
const KEY=import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabase=URL&&KEY?createClient(URL,KEY):null;
const localIdKey='christmas_draw_participant_id';
const getPid=()=>{let v=localStorage.getItem(localIdKey);if(!v){v=crypto.randomUUID();localStorage.setItem(localIdKey,v)}return v;};

function App(){
 const [pid]=useState(getPid),[name,setName]=useState(''),[submittedGift,setSubmittedGift]=useState('');
 const [participant,setParticipant]=useState(null),[participants,setParticipants]=useState([]),[count,setCount]=useState(25),[total,setTotal]=useState(0);
 const [drawCompleted,setDrawCompleted]=useState(false),[myVotes,setMyVotes]=useState([]);
 const [adminOpen,setAdminOpen]=useState(false),[password,setPassword]=useState(''),[adminOk,setAdminOk]=useState(false);
 const [adminParticipants,setAdminParticipants]=useState([]),[voteCounts,setVoteCounts]=useState([]),[votesRevealed,setVotesRevealed]=useState(false);
 const [limitInput,setLimitInput]=useState(25),[resetPassword,setResetPassword]=useState('');
 const [busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[configured,setConfigured]=useState(Boolean(supabase));

 async function load(){
  if(!supabase){setConfigured(false);return}
  const {data:event,error}=await supabase.rpc('public_event');
  if(error){setNotice('雲端資料庫尚未完成更新，請先執行新版 SQL migration。');return}
  setConfigured(true);const limit=Number(event?.participant_limit||25);
  setCount(limit);setLimitInput(limit);setDrawCompleted(Boolean(event?.draw_completed));setTotal(Number(event?.participant_count||0));
  const {data:mine}=await supabase.rpc('my_draw',{p_participant_id:pid});
  const me=mine?.[0]||null;setParticipant(me);
  const {data:votes}=await supabase.rpc('my_votes',{p_participant_id:pid});
  setMyVotes((votes||[]).map(x=>x.target_participant_id));
  if(event?.draw_completed){
   const {data:list}=await supabase.rpc('public_revealed_participants');
   setParticipants(list||[]);setTotal((list||[]).length);
  }else{
   setParticipants([]);
  }
 }
 useEffect(()=>{load();if(!supabase)return;const poll=setInterval(load,5000);return()=>clearInterval(poll)},[]);

 async function draw(e){
  e.preventDefault();
  if(!name.trim())return setNotice('請輸入姓名');
  if(!submittedGift.trim())return setNotice('請輸入你準備的禮物');
  setBusy(true);setNotice('');
  const {data,error}=await supabase.rpc('draw_number',{p_name:name.trim(),p_participant_id:pid,p_submitted_gift:submittedGift.trim()});
  if(error)setNotice(error.message);else{setParticipant({number:data.number,name:data.name,submitted_gift:data.gift});setNotice('登記成功並抽籤完成！請記住你的號碼。');await load()}
  setBusy(false);
 }
 async function login(){
  setBusy(true);const {data,error}=await supabase.rpc('admin_check',{p_password:password});
  if(error||!data){setNotice('管理員密碼錯誤');setAdminOk(false)}
  else{setAdminOk(true);setVotesRevealed(false);setVoteCounts([]);await loadAdminParticipants();setNotice('管理員驗證成功')}
  setBusy(false);
 }
 async function loadAdminParticipants(){
  if(!password)return;
  const {data,error}=await supabase.rpc('admin_list_voters',{p_password:password});
  if(error)setNotice(error.message);else setAdminParticipants(data||[]);
 }
 async function completeDraw(){
  if(!window.confirm('確定所有人都已完成登記？按下後會公開所有人的姓名與禮物，並開放投票。'))return;
  setBusy(true);const {data,error}=await supabase.rpc('admin_complete_draw',{p_password:password});
  if(error)setNotice(error.message);else{setNotice('抽選完畢！已公開所有人的姓名與禮物，匿名投票正式開放。');await load();await loadAdminParticipants()}
  setBusy(false);
 }
 async function revealVotes(){
  setBusy(true);const {data,error}=await supabase.rpc('admin_vote_counts',{p_password:password});
  if(error)setNotice(error.message);else{setVoteCounts(data||[]);setVotesRevealed(true);setNotice('已揭曉最終票數')}
  setBusy(false);
 }
 async function castVote(targetId){
  if(!participant)return setNotice('請先完成登記與抽籤');
  if(!drawCompleted)return setNotice('管理員尚未宣布抽選完畢');
  if(myVotes.includes(targetId))return setNotice('你已經投過這份禮物，不能重複投票');
  if(myVotes.length>=3)return setNotice('每人只有 3 票，你的票數已用完');
  setBusy(true);const {error}=await supabase.rpc('cast_gift_vote',{p_participant_id:pid,p_target_participant_id:targetId});
  if(error)setNotice(error.message);else setNotice('投票成功！你的投票是匿名的。');
  await load();setBusy(false);
 }
 async function resetPersonVotes(person){
  if(!window.confirm('確定清除「'+person.display_name+'」的全部投票紀錄？清除後可重新投 3 票。'))return;
  setBusy(true);const {error}=await supabase.rpc('admin_reset_participant_votes',{p_password:password,p_participant_id:person.participant_id});
  if(error)setNotice(error.message);else{setVotesRevealed(false);setVoteCounts([]);await loadAdminParticipants();if(person.participant_id===pid)await load();setNotice('已清除該參加者的投票紀錄')}
  setBusy(false);
 }
 async function saveLimit(){
  const v=Number(limitInput);if(!Number.isInteger(v)||v<1||v>25)return setNotice('人數必須介於 1 到 25 人');
  setBusy(true);const {error}=await supabase.rpc('admin_set_limit',{p_password:password,p_limit:v});
  if(error)setNotice(error.message);else{setNotice('登記人數已更新');await load()}setBusy(false);
 }
 async function resetAll(){
  if(!resetPassword)return setNotice('請再次輸入管理員密碼確認重置');
  if(!window.confirm('確定全部 Reset？會清除所有參加者、禮物登記、抽籤與投票資料，無法復原。'))return;
  setBusy(true);const {error}=await supabase.rpc('admin_reset_event',{p_password:resetPassword});
  if(error)setNotice(error.message);else{setParticipant(null);setName('');setSubmittedGift('');setMyVotes([]);setResetPassword('');setNotice('全部 Reset 完成，人數與管理員密碼保留。');await load();await loadAdminParticipants()}
  setBusy(false);
 }
 async function copyLink(){await navigator.clipboard.writeText(location.href);setNotice('活動連結已複製')}
 const remaining=Math.max(0,count-total);
 const sorted=useMemo(()=>[...participants].sort((a,b)=>a.draw_number-b.draw_number),[participants]);
 return <main className="shell">
  <header><div className="snow"><Snowflake/><Snowflake/><Snowflake/></div><div className="brand">CHRISTMAS <span>✦</span> 2026</div><h1>聖誕幸運抽籤</h1><p>Share the joy · Find your lucky gift</p><div className="ornament">🎄　🎁　❄️　🎅　❄️　🎁</div></header>
  <section className="stats"><div><Users/><b>{count}</b><small>抽籤名額</small></div><div><Gift/><b>{total}</b><small>已登記人數</small></div><div><Sparkles/><b>{remaining}</b><small>剩餘名額</small></div></section>
  {!configured?<section className="panel"><h2>雲端服務尚未設定</h2><p>請先完成 Supabase 設定。</p></section>:<>
   {!participant?<form className="panel" onSubmit={draw}><div className="section-title"><Gift/><h2>登記你的聖誕禮物並抽號碼</h2></div><label>你的姓名</label><input value={name} onChange={e=>setName(e.target.value)} maxLength="40" placeholder="請輸入姓名" required/><label>你準備的禮物</label><input value={submittedGift} onChange={e=>setSubmittedGift(e.target.value)} maxLength="100" placeholder="請輸入禮物名稱" required/><button disabled={busy||drawCompleted||total>=count} className="primary">{busy?'處理中…':'🎁 登記並抽籤'}</button><p className="hint">每人限登記一次。抽籤完成前，其他參加者看不到你的姓名與禮物。</p></form>:<section className="panel result"><div>YOUR LUCKY NUMBER</div><div className="big-number">{String(participant.number).padStart(2,'0')}</div><h2>恭喜 {participant.name}！</h2><p>你的禮物已完成登記，抽籤號碼已固定。</p><p className="own-gift">你登記的禮物：<b>{participant.submitted_gift||'已登記'}</b></p></section>}
   {!drawCompleted?<section className="panel"><div className="section-title"><LockKeyhole/><h2>等待管理員宣布抽選完畢</h2></div><p className="hint">目前尚未公開任何人的姓名與禮物。管理員確認所有人都完成登記後，會按下「抽選完畢」，屆時才會公開清單並開放投票。</p><div className="vote-summary">目前登記進度：<b>{total} / {count}</b></div></section>:<section className="panel"><div className="section-title"><Gift/><h2>聖誕禮物公開清單</h2><span className="live">VOTING OPEN</span></div><p className="hint">所有人的姓名、抽籤號碼與禮物已公開。每人有 3 票，每份禮物只能投 1 次；投票者身分不會公開。</p><div className="vote-summary">{participant?<>你已使用 <b>{myVotes.length}</b> / 3 票，剩餘 <b>{Math.max(0,3-myVotes.length)}</b> 票</>:'完成登記後即可匿名投票'}</div><div className="gift-grid">{sorted.map(person=><article className="gift-card" key={person.participant_id}><div className="number">{String(person.draw_number).padStart(2,'0')} 號</div><div className="gift-name">{person.submitted_gift}</div><div className="gift-owner">{person.display_name}</div><div className="vote-footer"><button className={myVotes.includes(person.participant_id)?'voted':'vote-button'} onClick={()=>castVote(person.participant_id)} disabled={busy||!participant||myVotes.includes(person.participant_id)||myVotes.length>=3||person.participant_id===pid}>{person.participant_id===pid?'自己的禮物':myVotes.includes(person.participant_id)?'已投票':myVotes.length>=3?'票數已用完':'投一票'}</button></div></article>)}</div></section>}
  </>}
  <footer><button className="ghost" onClick={copyLink}><Copy size={16}/> 複製活動連結</button><button className="ghost" onClick={()=>{const next=!adminOpen;setAdminOpen(next);setAdminOk(false);setPassword("");setResetPassword("");setAdminParticipants([]);setVoteCounts([]);setVotesRevealed(false)}}><LockKeyhole size={16}/> 管理員</button></footer>
  {adminOpen&&<section className="panel admin"><div className="section-title"><LockKeyhole/><h2>管理員後台</h2></div>{!adminOk?<><label>管理員密碼</label><input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="輸入管理員密碼"/><button className="primary" onClick={login} disabled={busy}>登入管理員</button></>:<>
   <p className="hint">管理員可查看所有登記者資料；一般參加者在抽選完成前無法取得此清單。</p>
   <div className="limit-row"><label>登記人數上限</label><input type="number" min="1" max="25" value={limitInput} onChange={e=>setLimitInput(e.target.value)}/><button onClick={saveLimit} disabled={busy||drawCompleted}>更新人數</button></div>
   <div className="admin-list">{adminParticipants.map(person=><div className="admin-person" key={person.participant_id}><b>{String(person.draw_number).padStart(2,'0')} 號｜{person.display_name}</b><span>禮物：{person.submitted_gift||'未填寫'}</span><small>已投 {person.vote_count} 票</small>{drawCompleted&&<button className="danger small-danger" onClick={()=>resetPersonVotes(person)} disabled={busy}>重設此人投票</button>}</div>)}</div>
   {!drawCompleted?<button className="primary complete-draw" onClick={completeDraw} disabled={busy||adminParticipants.length!==count}> <CheckCircle2 size={17}/> 抽選完畢並開放投票（{adminParticipants.length}/{count}）</button>:<><button className="primary" onClick={revealVotes} disabled={busy}>{votesRevealed?'重新揭曉最終票數':'揭曉最終票數'}</button>{votesRevealed&&<div className="admin-list">{voteCounts.map(x=><div className="admin-person" key={x.target_participant_id}><b>{String(x.draw_number).padStart(2,'0')} 號｜{x.display_name}</b><span>{x.submitted_gift}</span><strong>🗳️ {x.vote_count} 票</strong></div>)}</div>}</>}
   <div className="reset-box"><div className="section-title"><RotateCcw/><h3>全部 Reset</h3></div><p className="hint">清除所有參加者、禮物登記、抽籤與投票資料；人數上限及管理員密碼保留。</p><label>再次輸入管理員密碼</label><input type="password" value={resetPassword} onChange={e=>setResetPassword(e.target.value)} placeholder="輸入管理員密碼以確認 Reset"/><button className="danger" onClick={resetAll} disabled={busy}>全部 Reset</button></div>
   <button className="ghost" onClick={()=>{setAdminOk(false);setPassword('');setResetPassword('');setAdminParticipants([]);setVoteCounts([]);setVotesRevealed(false)}}><LogOut size={16}/> 登出</button>
  </>}</section>}
  {notice&&<div className="notice" role="status">{notice}<button onClick={()=>setNotice('')}>×</button></div>}
  <p className="fine">Made with 🎄 for a joyful Christmas</p>
 </main>;
}
createRoot(document.getElementById('root')).render(<App/>);

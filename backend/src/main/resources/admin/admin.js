'use strict';
const $ = id => document.getElementById(id);
const labels = {ORIGINAL:'作品管理',ASSIGNMENT:'作业管理',COMMENTS:'评论管理'};
const state = {section:'ORIGINAL',status:'ACTIVE',q:'',postId:null,postTitle:'',offset:0,limit:20,total:0,sequence:0,authenticated:false};
let detailTarget = null, deleteTarget = null, deleting = false, toastTimer;
function el(tag, className, text) { const node=document.createElement(tag); if(className)node.className=className; if(text!=null)node.textContent=String(text); return node; }
function date(value) { return value ? new Date(value).toLocaleString('zh-CN',{hour12:false}) : '—'; }
function safeImage(value) { try { const url=new URL(value); return url.protocol==='https:' ? url.href : null; } catch { return null; } }
function toast(message) { $('toast').textContent=message; $('toast').hidden=false; clearTimeout(toastTimer); toastTimer=setTimeout(()=>$('toast').hidden=true,4500); }
function showLogin() { state.authenticated=false; state.sequence++; $('workspace').hidden=true; $('login-screen').hidden=false; $('detail-dialog').close(); $('delete-dialog').close(); $('table-body').replaceChildren(); $('detail-content').replaceChildren(); detailTarget=null; deleteTarget=null; }
async function api(path, options={}) {
  const response=await fetch('/api/admin'+path,{credentials:'same-origin',cache:'no-store',...options,headers:{'Content-Type':'application/json',...(options.method&&options.method!=='GET'?{'X-Lumen-Admin':'1'}:{}),...options.headers}});
  const data=response.status===204?null:await response.json().catch(()=>null);
  if(!response.ok) { if((response.status===401||response.status===403)&&path!=='/login'&&state.authenticated)showLogin(); throw new Error(data?.error||(response.status===401?'登录已过期，请重新登录':'请求失败，请稍后重试')); }
  return data;
}
async function enter(user) { state.authenticated=true; $('login-screen').hidden=true; $('workspace').hidden=false; $('admin-name').textContent=user.name; await refresh(); }
$('login-form').addEventListener('submit',async event=>{
  event.preventDefault(); $('login-button').disabled=true; $('login-error').textContent='';
  try { const user=await api('/login',{method:'POST',body:JSON.stringify({email:$('email').value.trim(),password:$('password').value})}); $('password').value=''; await enter(user); }
  catch(error){$('login-error').textContent=error.message;} finally{$('login-button').disabled=false;}
});
$('logout-button').addEventListener('click',async()=>{try{await api('/logout',{method:'POST'});showLogin();}catch(error){toast(error.message);}});
function setSection(section) {
  state.section=section;state.offset=0;state.q='';state.postId=null;state.postTitle='';$('search').value='';
  document.querySelectorAll('[data-section]').forEach(button=>{const active=button.dataset.section===section;button.classList.toggle('active',active);if(active)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');});
  $('page-title').textContent=labels[section];$('breadcrumb').textContent=labels[section];
  $('page-description').textContent=section==='COMMENTS'?'查看社区交流，及时处理不合适的评论。':section==='ASSIGNMENT'?'查看用户的复刻成果与拍摄心得。':'查看用户创作，维护社区内容。';
  $('search').placeholder=section==='COMMENTS'?'搜索评论、作者或作品标题':'搜索标题、作者或内容 ID';
}
document.querySelectorAll('[data-section]').forEach(button=>button.addEventListener('click',()=>{setSection(button.dataset.section);loadList();}));
document.querySelectorAll('[data-status]').forEach(button=>button.addEventListener('click',()=>{state.status=button.dataset.status;state.offset=0;document.querySelectorAll('[data-status]').forEach(item=>{const selected=item===button;item.classList.toggle('selected',selected);item.setAttribute('aria-pressed',selected);});loadList();}));
$('search-form').addEventListener('submit',event=>{event.preventDefault();state.q=$('search').value.trim();state.offset=0;loadList();});
$('search').addEventListener('search',()=>{if(!$('search').value){state.q='';state.offset=0;loadList();}});
$('previous').addEventListener('click',()=>{state.offset=Math.max(0,state.offset-state.limit);loadList();});
$('next').addEventListener('click',()=>{state.offset+=state.limit;loadList();});
$('refresh-button').addEventListener('click',refresh);
$('clear-post-filter').addEventListener('click',()=>{state.postId=null;state.offset=0;loadList();});
async function refresh() {
  $('refresh-button').disabled=true;
  await Promise.all([loadList(),loadStats()]);
  $('refresh-button').disabled=false;
}
async function loadStats() {try{const stats=await api('/stats');if(!state.authenticated)return;for(const key of ['originals','assignments','comments','deleted']){ $('stat-'+key).textContent=stats[key].toLocaleString(); if($('nav-'+key))$('nav-'+key).textContent=stats[key].toLocaleString(); }}catch(error){if(state.authenticated)toast(error.message);}}
function action(text,callback,danger=false){const button=el('button','text-button'+(danger?' delete':''),text);button.addEventListener('click',callback);return button;}
function badge(deleted,hidden=false){return el('span','badge'+(deleted?' deleted':hidden?' hidden':''),deleted?'已删除':hidden?'已隐藏':'正常');}
function image(value,className){const url=safeImage(value);if(!url)return el('div',className==='thumb'?'thumb thumb-placeholder':'detail-placeholder','暂无图片');const img=el('img',className);img.src=url;img.alt='作品照片';img.loading='lazy';img.referrerPolicy='no-referrer';img.addEventListener('error',()=>{img.replaceWith(el('div',className==='thumb'?'thumb thumb-placeholder':'detail-placeholder','图片暂不可用'));},{once:true});return img;}
async function loadList() {
  const sequence=++state.sequence, section=state.section;
  $('loading').hidden=false;$('empty').hidden=true;$('table-wrap').hidden=true;$('list-error').hidden=true;$('previous').disabled=true;$('next').disabled=true;$('page-info').textContent='加载中…';
  $('post-filter').hidden=!state.postId;$('post-filter-label').textContent=state.postId?'当前评论所属内容：'+state.postTitle:'';
  const params=new URLSearchParams({status:state.status,q:state.q,limit:state.limit,offset:state.offset});
  if(section!=='COMMENTS')params.set('kind',section);else if(state.postId)params.set('postId',state.postId);
  try {
    const page=await api((section==='COMMENTS'?'/comments':'/posts')+'?'+params);
    if(sequence!==state.sequence||!state.authenticated)return;
    if(!page.items.length&&state.offset>0){state.offset=Math.max(0,state.offset-state.limit);return loadList();}
    state.total=page.total;renderRows(page.items,section);
    $('empty').hidden=page.items.length>0;$('table-wrap').hidden=!page.items.length;
    $('empty-description').textContent=state.q||state.postId?'没有符合筛选条件的内容，请尝试其他关键词。':state.status==='DELETED'?'目前没有已删除的记录。':'用户发布的内容会显示在这里。';
    $('page-info').textContent=`共 ${page.total} 条 · 第 ${Math.floor(state.offset/state.limit)+1} / ${Math.max(1,Math.ceil(page.total/state.limit))} 页`;
    $('previous').disabled=state.offset===0;$('next').disabled=state.offset+page.items.length>=page.total;
  } catch(error){if(sequence===state.sequence&&state.authenticated){$('list-error').textContent=error.message+'，可点击“刷新数据”重试。';$('list-error').hidden=false;$('page-info').textContent='加载失败';}}
  finally{if(sequence===state.sequence)$('loading').hidden=true;}
}
function renderRows(items,section) {
  const header=el('tr');for(const text of section==='COMMENTS'?['评论内容','作者 / 所属内容','发布时间','状态','操作']:['内容','作者','发布时间','互动','状态','操作'])header.append(el('th','',text));$('table-head').replaceChildren(header);$('table-body').replaceChildren();
  for(const item of items){const row=el('tr'),content=el('td'),author=el('td');const isComment=section==='COMMENTS',deleted=isComment?item.status==='DELETED':!!item.deletedAt;
    if(isComment){content.append(el('div','comment-text',item.content));author.append(el('div','author-name',item.authorName),el('div','content-subtitle',(item.postDeleted?'[原内容已删除] ':'')+item.postTitle));}
    else{const cell=el('div','content-cell'),copy=el('div');copy.append(el('div','content-title',item.title),el('div','content-subtitle',item.description||'暂无作品说明'));cell.append(image(item.imageUrl,'thumb'),copy);content.append(cell);author.append(el('div','author-name',item.authorName));}
    row.append(content,author,el('td','date',date(item.createdAt)));
    if(!isComment)row.append(el('td','date',`${item.likeCount} 赞 · ${item.commentCount} 评论`));
    const status=el('td');status.append(badge(deleted,item.status==='HIDDEN'));row.append(status);
    const actions=el('td'),group=el('div','actions');group.append(action('查看',()=>isComment?openComment(item):openPost(item.id)));
    if(!deleted)group.append(action('删除',()=>confirmDelete({type:isComment?'comments':'posts',id:item.id,label:isComment?item.content:item.title}),true));actions.append(group);row.append(actions);$('table-body').append(row);
  }
}
function field(list,label,value){if(value==null||value==='')return;list.append(el('dt','',label),el('dd','',value));}
function setDetailActions(target,deleted){detailTarget=target;$('detail-delete').hidden=deleted;$('detail-comments').hidden=target.type==='comments';}
async function openPost(id) {
  detailTarget={type:'posts',id};$('detail-title').textContent='内容详情';$('detail-content').replaceChildren(el('div','dialog-loading','正在加载详情…'));$('detail-delete').hidden=true;$('detail-comments').hidden=true;$('detail-dialog').showModal();
  try{const detail=await api('/posts/'+encodeURIComponent(id));if(detailTarget?.id!==id||!$('detail-dialog').open)return;const post=detail.content;$('detail-title').textContent=post.title;
    const grid=el('div','detail-grid'),visual=el('div'),fields=el('dl','detail-fields');visual.append(image(post.image?.displayUrl||post.image?.originalUrl,'detail-image'));
    field(fields,'内容类型',post.kind==='ASSIGNMENT'?'复刻作业':'原创作品');field(fields,'作者',post.author?.name);field(fields,'发布时间',date(detail.createdAt));field(fields,'状态',detail.deletedAt?'已删除 · '+date(detail.deletedAt):'未删除');field(fields,'内容 ID',post.id);field(fields,'关联原作 ID',post.originalId);field(fields,'作品说明',post.description);field(fields,'作品标签',post.tags?.join(' / '));field(fields,'拍摄地点',[post.location?.city,post.location?.name,post.location?.detailedAddress].filter(Boolean).join(' · '));
    for(const [key,label]of Object.entries({shootingNotes:'拍摄思路',editingNotes:'后期说明',reusedNotes:'沿用内容',adjustedNotes:'调整内容',assignmentNotes:'拍摄心得'}))field(fields,label,post[key]);
    field(fields,'拍摄参数',[post.metadata?.camera,post.metadata?.lens,post.metadata?.focalLengthMm&&post.metadata.focalLengthMm+'mm',post.metadata?.aperture&&'f/'+post.metadata.aperture,post.metadata?.iso&&'ISO '+post.metadata.iso].filter(Boolean).join(' · '));
    grid.append(visual,fields);$('detail-content').replaceChildren(grid);setDetailActions({type:'posts',id:post.id,label:post.title},!!detail.deletedAt);
  }catch(error){if($('detail-dialog').open)$('detail-content').replaceChildren(el('p','detail-full error',error.message));}
}
function openComment(item){$('detail-title').textContent='评论详情';const fields=el('dl','detail-fields detail-full');field(fields,'评论内容',item.content);field(fields,'作者',item.authorName);field(fields,'所属内容',item.postTitle+(item.postDeleted?'（已删除）':''));field(fields,'发布时间',date(item.createdAt));field(fields,'评论 ID',item.id);field(fields,'状态',item.status==='DELETED'?'已删除':item.status==='HIDDEN'?'已隐藏':'正常');$('detail-content').replaceChildren(fields);setDetailActions({type:'comments',id:item.id,label:item.content},item.status==='DELETED');$('detail-dialog').showModal();}
$('detail-close').addEventListener('click',()=>$('detail-dialog').close());
$('detail-dialog').addEventListener('close',()=>{detailTarget=null;});
$('detail-delete').addEventListener('click',()=>{if(detailTarget)confirmDelete({...detailTarget});});
$('detail-comments').addEventListener('click',()=>{if(!detailTarget)return;const target={...detailTarget};$('detail-dialog').close();setSection('COMMENTS');state.postId=target.id;state.postTitle=target.label;loadList();});
function confirmDelete(target){deleteTarget=target;$('delete-label').textContent=target.label;$('delete-explanation').textContent=target.type==='posts'?'该内容下的评论也将不再公开展示。关联的复刻作业不会被连带删除。':'仅删除此条评论，同时更新所属内容的评论数量。';$('delete-error').textContent='';$('delete-dialog').showModal();$('delete-cancel').focus();}
$('delete-cancel').addEventListener('click',()=>{if(!deleting)$('delete-dialog').close();});
$('delete-dialog').addEventListener('cancel',event=>{if(deleting)event.preventDefault();});
$('delete-confirm').addEventListener('click',async()=>{
  if(deleting||!deleteTarget)return;deleting=true;$('delete-confirm').disabled=true;$('delete-cancel').disabled=true;$('delete-confirm').textContent='正在删除…';const target={...deleteTarget};
  try{await api('/'+target.type+'/'+encodeURIComponent(target.id),{method:'DELETE'});$('delete-dialog').close();$('detail-dialog').close();toast('内容已删除，操作已记录');await refresh();}
  catch(error){$('delete-error').textContent=error.message;}finally{deleting=false;$('delete-confirm').disabled=false;$('delete-cancel').disabled=false;$('delete-confirm').textContent='确认删除';}
});
(async()=>{try{await enter(await api('/me'));}catch{showLogin();}})();

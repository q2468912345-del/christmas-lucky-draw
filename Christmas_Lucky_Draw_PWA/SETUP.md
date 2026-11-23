# Christmas Lucky Draw PWA — 部署指南

## 功能
- iOS / Android 可加入主畫面的 PWA（單一網址、雲端同步）
- 管理員設定人數上限 1–25；目前預設 25
- 參加者輸入姓名後抽取唯一號碼；同一裝置會保留抽籤結果
- 公開禮物清單；管理員密碼驗證後可修改禮物
- Supabase PostgreSQL RPC 以交易鎖避免同時抽籤重號

## 1. 建立 Supabase
1. 到 https://supabase.com 建立免費專案。
2. 你已在 Supabase SQL Editor 執行修正版 V2 SQL，請勿為了部署再次初始化或重設資料庫。
3. 管理員密碼已在第一次初始化時設定；不要把密碼交給參加者。
4. Project Settings → API，複製 Project URL 與 anon/public key。

## 2. 設定環境變數
複製 `.env.example` 為 `.env`，填入：
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

anon key 可放在前端；不可放 service_role key。資料表已啟用 RLS，所有讀寫透過受控 RPC。

## 3. 本機測試
需要 Node.js 20 或更新版本：
```bash
npm install
npm run dev
```
## 4. 正式部署（Vercel）
1. 將整個專案資料夾推送到你自己的 GitHub repository。
2. 在 https://vercel.com/new 匯入該 repository。
3. Framework 選 Vite；Build Command `npm run build`；Output Directory `dist`。
4. 在 Vercel Project → Settings → Environment Variables 加入兩個 VITE_SUPABASE 變數。
5. Deploy。取得正式 HTTPS 網址。

也可部署到 Netlify（Build `npm run build`、Publish `dist`），並設定相同環境變數。

## 5. QR Code
部署成功後，以正式 HTTPS 網址產生 QR Code。可用手機相機掃描測試。不要用 localhost 網址製作 QR Code。
可用以下指令產生 PNG：
```bash
python -m pip install qrcode[pil]
python -c "import qrcode; qrcode.make('https://YOUR-LIVE-APP-URL').save('christmas-lucky-draw-qr.png')"
```

## 重要產品限制／後續建議
- 目前參加者身分以姓名唯一；若可能有同名，建議改成「姓名＋個人識別碼／邀請碼」。
- 每位參加者的抽籤 ID 存在該手機瀏覽器；清除網站資料或換手機後，需由管理員協助恢復，否則無法自動找回原抽籤號碼。
- 此版本預設 25 個號碼；SQL 初始化的活動上限目前是 25。若需其他人數，需在管理功能增加人數設定與對應號碼。
- 禮物清單對所有人公開，這符合目前選擇。
- 正式公開前，建議先用測試姓名完成多手機測試，並確認管理員密碼已更換。

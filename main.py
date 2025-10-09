import os
import asyncio
from datetime import datetime, timedelta
import traceback
from typing import Optional, List, Dict
import json

import pandas as pd
from pydantic import BaseModel, Field as PydanticField
from fastapi import FastAPI, HTTPException, Query, BackgroundTasks, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
import httpx
from sqlalchemy import func
from sqlmodel import Relationship, SQLModel, Field, create_engine, Session, select, delete
import yfinance as yf
import redis.asyncio as redis

import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv
from sqlalchemy.orm import joinedload

# ----------------------
# .env, Config ve Firebase
# ----------------------
load_dotenv()

# --- YENİ GEREKLİ ORTAM DEĞİŞKENİ ---
# Cron job'unuzun endpoint'i çağırmak için kullanacağı gizli anahtar.
# Örnek: "my_super_secret_cron_key_123"
# Bu anahtarı hem hosting platformunuza hem de cron job servisinize eklemelisiniz.
CRON_SECRET_KEY = os.getenv("CRON_SECRET_KEY")
if not CRON_SECRET_KEY:
    raise ValueError("CRON_SECRET_KEY ortam değişkeni bulunamadı! Bu, cron job güvenliği için zorunludur.")

FINNHUB_API_KEY = os.getenv("FINNHUB_API_KEY")
FINNHUB_BASE = "https://finnhub.io/api/v1"

# Firebase initialization
firebase_json_str = os.getenv("FIREBASE_JSON")
if not firebase_json_str:
    raise ValueError("FIREBASE_JSON ortam değişkeni bulunamadı!")

cred_dict = json.loads(firebase_json_str)
cred_dict["private_key"] = cred_dict["private_key"].replace("\\n", "\n").replace("\r", "")

PLAN_LIMITS = {
    "free": 5,
    "pro": 20,
    "ultra": float('inf') # float('inf') means infinity
}

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_dict)
    firebase_admin.initialize_app(cred)

# ----------------------
# DB Yapılandırması
# ----------------------
DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    raise RuntimeError("DATABASE_URL bulunamadı! Railway'de Postgres URL tanımlı mı kontrol et.")

if DB_URL.startswith("postgres://"):
    DB_URL = DB_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(DB_URL, echo=False)

REDIS_URL = os.getenv("REDIS_URL")
if not REDIS_URL:
    raise ValueError("REDIS_URL ortam değişkeni bulunamadı! Railway'den veya .env'den geldiğinden emin olun.")

# from_url fonksiyonu, bağlantı havuzunu (connection pool) otomatik yönetir.
redis_conn = redis.from_url(REDIS_URL, decode_responses=True)

# ----------------------
# FastAPI Uygulaması
# ----------------------
app = FastAPI(title="MarketWatcher Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------------------
# DB Modelleri
# ----------------------------
class Alert(SQLModel, table=True):
    __table_args__ = {"extend_existing": True}
    id: Optional[int] = Field(default=None, primary_key=True)
    user_uid: str = Field(foreign_key="user.uid", index=True)
    market: str
    symbol: str
    percentage: float
    base_price: float
    upper_limit: float
    lower_limit: float
    created_at: datetime = Field(default_factory=datetime.utcnow)

    user: "User" = Relationship(back_populates="alerts")

class AlertCreate(SQLModel):
    market: str
    symbol: str
    percentage: float
    user_uid: Optional[str] = None    

class UserSettings(SQLModel):
    notifications_enabled: bool
    language_code: str = Field(default="en") 

class User(UserSettings, table=True):
    uid: str = Field(primary_key=True)
    fcm_token: Optional[str] = Field(default=None, index=True)
    plan: str = Field(default="free", index=True) # free, pro, ultra
    last_checked_at: Optional[datetime] = Field(default=None)

    alerts: List["Alert"] = Relationship(back_populates="user")

# ----------------------------
# DB ve tablo oluşturma
# ----------------------------
def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

@app.on_event("startup")
def on_startup():
    create_db_and_tables()

class RevenueCatEvent(BaseModel):
    app_user_id: str = PydanticField(..., alias="app_user_id")
    entitlements: List[str] = PydanticField(..., alias="entitlements")

class RevenueCatWebhookPayload(BaseModel):
    event: RevenueCatEvent
    api_version: str

# Yeni ortam değişkenini kodun en üstünde diğerleri gibi okuyun
REVENUECAT_WEBHOOK_TOKEN = os.getenv("REVENUECAT_WEBHOOK_TOKEN")

@app.post("/webhooks/revenuecat")
async def handle_revenuecat_webhook(
    payload: RevenueCatWebhookPayload, 
    authorization: str = Header(None)
):
    """
    RevenueCat'ten gelen abonelik durumu değişikliklerini dinler ve
    veritabanındaki kullanıcı planını günceller.
    """
    # 1. Adım: İsteğin gerçekten RevenueCat'ten geldiğini doğrula
    if not REVENUECAT_WEBHOOK_TOKEN or authorization != f"Bearer {REVENUECAT_WEBHOOK_TOKEN}":
        print("KRİTİK GÜVENLİK UYARISI: Geçersiz RevenueCat webhook token'ı!")
        raise HTTPException(status_code=403, detail="Geçersiz Yetkilendirme")

    # 2. Adım: Gelen veriden kullanıcı ID'sini ve yetkilerini al
    user_uid = payload.event.app_user_id
    entitlements = payload.event.entitlements
    
    # 3. Adım: Yetkilere göre yeni planı belirle
    new_plan = "free" # Varsayılan olarak free
    if "ultra_access" in entitlements:
        new_plan = "ultra"
    elif "pro_access" in entitlements:
        new_plan = "pro"

    # 4. Adım: Veritabanındaki kullanıcıyı güncelle
    try:
        with Session(engine) as session:
            user = session.get(User, user_uid)
            if user:
                if user.plan != new_plan:
                    user.plan = new_plan
                    session.add(user)
                    session.commit()
                    print(f"Kullanıcı {user_uid} planı '{new_plan}' olarak güncellendi.")
                else:
                    print(f"Kullanıcı {user_uid} zaten '{new_plan}' planında. Değişiklik yapılmadı.")
            else:
                print(f"Webhook uyarısı: {user_uid} ID'li kullanıcı veritabanında bulunamadı.")
                # İsteğe bağlı: Bu durumda yeni bir kullanıcı da oluşturabilirsiniz.
                # Şimdilik sadece logluyoruz.
    
    except Exception as e:
        print(f"RevenueCat webhook işlenirken veritabanı hatası: {e}")
        # Hata durumunda RevenueCat'e başarısız olduğumuzu bildirmeyelim ki
        # webhook'u tekrar göndermeye çalışsın. Bu yüzden 500 hatası fırlatıyoruz.
        raise HTTPException(status_code=500, detail="Veritabanı güncelleme hatası.")

    # 5. Adım: RevenueCat'e her şeyin yolunda olduğunu bildir
    return {"status": "ok"}
# ----------------------------
# --- YENİ CRON JOB ENDPOINT'i ve MANTIĞI ---
# ----------------------------
# --- run_price_checks fonksiyonunu bu yeni versiyonla değiştirin ---

# Bu yardımcı fonksiyon, kodu daha temiz tutmak için
async def check_alerts_for_user(user: User, prices: Dict):
    # CHANGED: Instead of taking data from the database, we take it from the user object directly.
    user_alerts = user.alerts
    if not user_alerts:
        return []

    alerts_to_delete_ids = []
    for alert in user_alerts:
        lang_code = user.language_code if user.language_code in NOTIFICATION_TEMPLATES else "en"
        template = NOTIFICATION_TEMPLATES[lang_code]
        localized_symbol = METAL_LOCALIZATION_MAP.get(alert.symbol, {}).get(lang_code, alert.symbol)
        
        current_price = prices.get(alert.symbol)
        if current_price is None:
            continue

        if current_price >= alert.upper_limit or current_price <= alert.lower_limit:
            if user.notifications_enabled and user.fcm_token:
                is_increase = current_price >= alert.upper_limit
                direction_text = template["increased"] if is_increase else template["decreased"]
                
                title = template["title"].format(symbol=localized_symbol)
                body = template["body"].format(
                    symbol=localized_symbol,
                    percentage=alert.percentage,
                    direction=direction_text,
                    price=current_price
                )
                send_push_notification(token=user.fcm_token, title=title, body=body)
            
            alerts_to_delete_ids.append(alert.id)
    return alerts_to_delete_ids

# Bu fonksiyonları kodunuzun uygun bir yerine (örn: price_fetcher.py veya main.py'ın üst kısımları) ekleyebilirsiniz.
# Bunlar, toplu veri çekme işlemini yapacak yardımcı fonksiyonlardır.

async def fetch_bist_batch(symbols: set) -> dict:
    """Verilen BIST sembol listesi için yfinance'tan toplu fiyat çeker."""
    if not symbols:
        return {}
    
    prices = {}
    yf_symbols = [s if s.endswith(".IS") else f"{s}.IS" for s in symbols]
    try:
        data = yf.download(yf_symbols, period="1d", progress=False, auto_adjust=True)['Close']
        if data.empty:
            return {}
        
        # yfinance'tan gelen sonuç tek bir sembol içinse Series, çoklu ise DataFrame olur.
        if isinstance(data, pd.Series): # Tek sembol durumu
             if not data.dropna().empty:
                short_symbol = yf_symbols[0].split('.')[0]
                prices[short_symbol] = round(float(data.dropna().iloc[-1]), 2)
        else: # Çoklu sembol durumu
            for yf_symbol in yf_symbols:
                short_symbol = yf_symbol.split('.')[0]
                if yf_symbol in data and not data[yf_symbol].dropna().empty:
                    prices[short_symbol] = round(float(data[yf_symbol].dropna().iloc[-1]), 2)
    except Exception as e:
        print(f"KRİTİK HATA (Toplu BIST): {e}")
    return prices

async def fetch_nasdaq_batch(symbols: set) -> dict:
    """Verilen NASDAQ sembol listesi için Finnhub'tan toplu fiyat çeker."""
    if not symbols:
        return {}
    
    prices = {}
    async with httpx.AsyncClient(timeout=15) as client:
        tasks = [client.get(f"{FINNHUB_BASE}/quote", params={"symbol": sym, "token": FINNHUB_API_KEY}) for sym in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
        
        for sym, r in zip(symbols, responses):
            if not isinstance(r, Exception) and r.status_code == 200:
                price_val = r.json().get("c")
                if price_val:
                    prices[sym] = round(price_val, 2)
    return prices

async def fetch_crypto_batch(symbols: set) -> dict:
    """Verilen CRYPTO sembol listesi için Binance'ten toplu fiyat çeker."""
    if not symbols:
        return {}
        
    prices = {}
    # Binance API için sembollerin sonuna "USDT" eklenir
    binance_symbols = [f"{s.upper()}USDT" for s in symbols]
    async with httpx.AsyncClient(timeout=15) as client:
        tasks = [client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": s}) for s in binance_symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
        
        for original_sym, r in zip(symbols, responses):
            if not isinstance(r, Exception) and r.status_code == 200:
                data = r.json()
                price_val = data.get("price")
                if price_val:
                    prices[original_sym] = round(float(price_val), 2)
    return prices

async def fetch_metals_batch(symbols: set) -> dict:
    """Verilen METAL sembolleri (ALTIN, GÜMÜŞ vb.) için toplu fiyat çeker."""
    if not symbols:
        return {}

    prices = {}
    metals_yf_map = {"ALTIN": "GC=F", "GÜMÜŞ": "SI=F", "BAKIR": "HG=F"}
    # Sadece istenen metallerin yf ticker'larını ve her zaman gereken TRY=X'i al
    yf_tickers_to_fetch = {metals_yf_map[s] for s in symbols if s in metals_yf_map}
    yf_tickers_to_fetch.add("TRY=X")
    
    try:
        data = yf.download(list(yf_tickers_to_fetch), period="1d", progress=False, auto_adjust=True)['Close']
        if data.empty:
            return {}

        usdtry_rate = data["TRY=X"].dropna().iloc[-1]
        
        for metal_name, yf_ticker in metals_yf_map.items():
            if metal_name in symbols and yf_ticker in data and not data[yf_ticker].dropna().empty:
                price_usd = data[yf_ticker].dropna().iloc[-1]
                # Gram/TL fiyatını hesapla
                prices[metal_name] = round((price_usd * usdtry_rate) / 31.1035, 2)
    except Exception as e:
        print(f"KRİTİK HATA (Toplu METALS): {e}")
    return prices

# --- ANA FONKSİYON ---

async def run_price_checks():
    print("Arka plan fiyat kontrolü başladı...")
    now = datetime.utcnow()
    try:
        with Session(engine) as session:
            # 1. ADIM: KULLANICILARI VE ALARMLARI ÇEKME
            query = select(User).options(joinedload(User.alerts))
            all_users = session.exec(query).unique().all()
            if not all_users:
                print("Kontrol edilecek kullanıcı bulunamadı."); return

            # 2. ADIM: KONTROL ZAMANI GELEN KULLANICILARI FİLTRELEME
            users_to_check = []
            for user in all_users:
                plan = user.plan
                last_checked = user.last_checked_at or datetime.min
                check_interval = timedelta(minutes=10)
                if plan == 'ultra': check_interval = timedelta(minutes=1)
                elif plan == 'pro': check_interval = timedelta(minutes=3)
                if (now - last_checked) >= check_interval:
                    users_to_check.append(user)
            
            if not users_to_check:
                print("Kontrol zamanı gelen kullanıcı yok. Görev sonlandırıldı."); return

            # 3. ADIM: SEMBOLLERİ PİYASALARINA GÖRE GRUPLAMA
            symbols_by_market = {"BIST": set(), "NASDAQ": set(), "CRYPTO": set(), "METALS": set()}
            for user in users_to_check:
                for alert in user.alerts:
                    market = alert.market.upper()
                    if market in symbols_by_market:
                        symbols_by_market[market].add(alert.symbol)
            
            # 4. ADIM: HER PİYASA İÇİN TOPLU VERİ ÇEKME
            prices = {}
            
            batch_tasks = []
            if symbols_by_market["BIST"]:
                batch_tasks.append(fetch_bist_batch(symbols_by_market["BIST"]))
            if symbols_by_market["NASDAQ"]:
                batch_tasks.append(fetch_nasdaq_batch(symbols_by_market["NASDAQ"]))
            if symbols_by_market["CRYPTO"]:
                batch_tasks.append(fetch_crypto_batch(symbols_by_market["CRYPTO"]))
            if symbols_by_market["METALS"]:
                batch_tasks.append(fetch_metals_batch(symbols_by_market["METALS"]))

            if batch_tasks:
                list_of_price_dicts = await asyncio.gather(*batch_tasks)
                for price_dict in list_of_price_dicts:
                    prices.update(price_dict)
            
            # =======================================================================
            # === YENİ REDIS ENTEGRASYONU BURADA BAŞLIYOR ===
            # =======================================================================
            # Toplu halde çekilen tüm güncel fiyatları Redis'e yazıyoruz.
            # Bu sayede /prices endpoint'i bu hazır veriyi anında ve masrafsızca okuyabilir.
            if prices:
                try:
                    # Fiyatları JSON formatına çevirip Redis'e 90 saniye geçerli olacak şekilde kaydediyoruz.
                    # 'ex=90' parametresi, anahtarın 90 saniye sonra otomatik silinmesini sağlar.
                    await redis_conn.set("all_market_prices", json.dumps(prices), ex=90)
                    print(f"{len(prices)} adet sembol fiyatı Redis cache'ine yazıldı.")
                except Exception as redis_e:
                    # Redis'e yazılamazsa bile programın çökmesini engelle, sadece hata bas.
                    print(f"KRİTİK REDIS HATASI: Cache'e yazılamadı. Hata: {redis_e}")
            # =======================================================================
            # === REDIS ENTEGRASYONU BURADA BİTİYOR ===
            # =======================================================================
            
            # 5. ADIM: ALARMLARI KONTROL ETME VE SİLME
            # Bu adım, az önce API'lerden taze çektiğimiz 'prices' sözlüğünü kullanmaya devam eder.
            # Redis'e yazma işlemi, sadece diğer endpoint'lerin veriye ulaşması içindir.
            total_deleted_alerts = []
            for user in users_to_check:
                deleted_ids = await check_alerts_for_user(user, prices)
                total_deleted_alerts.extend(deleted_ids)
                user.last_checked_at = now
                session.add(user)

            if total_deleted_alerts:
                delete_stmt = delete(Alert).where(Alert.id.in_(total_deleted_alerts))
                session.exec(delete_stmt)
            
            session.commit()
            if total_deleted_alerts:
                print(f"{len(total_deleted_alerts)} adet tetiklenen alarm silindi.")
            print(f"{len(users_to_check)} kullanıcının alarmları kontrol edildi.")

    except Exception as e:
        print(f"KRİTİK HATA (run_price_checks): {e}")
        traceback.print_exc()
    
    print("Arka plan fiyat kontrolü tamamlandı.")

def verify_cron_secret(secret: str = Query(...)):
    """Dependency to verify the cron job secret key."""
    if secret != CRON_SECRET_KEY:
        raise HTTPException(status_code=403, detail="Geçersiz veya eksik gizli anahtar.")
    return True

@app.post("/run-checks", status_code=202)
async def trigger_price_checks(
    background_tasks: BackgroundTasks, 
    is_secret_valid: bool = Depends(verify_cron_secret)
):
    """
    Bu endpoint, bir cron job tarafından çağrılmak üzere tasarlanmıştır.
    Fiyat kontrol işlemini arka planda başlatır ve hemen yanıt döner.
    """
    background_tasks.add_task(run_price_checks)
    return {"message": "Fiyat kontrol görevi arka planda başlatıldı."}

# ----------------------------
# CRUD for Alerts and Settings
# ----------------------------
@app.post("/user/register_token", status_code=200)
def register_token(user_uid: str = Query(...), token: str = Query(...)):
    """Kullanıcının FCM cihaz token'ını veritabanına kaydeder veya günceller."""
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # Kullanıcı yoksa, yeni bir kullanıcı oluştur ve token'ı ata.
            user = User(uid=user_uid, fcm_token=token, notifications_enabled=True, language_code='en')
        else:
            # Kullanıcı varsa, sadece token'ını güncelle.
            user.fcm_token = token
        session.add(user)
        session.commit()
    return {"status": "token registered successfully"}

# --- BU FONKSİYONU GÜNCELLEYİN ---

@app.post("/alerts", response_model=Alert)
async def create_alert(alert_in: AlertCreate):
    try:
        with Session(engine) as session:
            # 1. Adım: Kullanıcının planını ve mevcut alarm sayısını al
            user = session.get(User, alert_in.user_uid)
            if not user:
                raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

            user_plan = user.plan
            limit = PLAN_LIMITS.get(user_plan, 5) # Bilinmeyen bir plan varsa, free limiti uygulanır

            # Veritabanından kullanıcının mevcut alarm sayısını verimli bir şekilde say
            count_statement = select(func.count(Alert.id)).where(Alert.user_uid == alert_in.user_uid)
            user_alarm_count = session.exec(count_statement).one()
            
            # 2. Adım: Limiti kontrol et
            if user_alarm_count >= limit:
                # Eğer kullanıcı limitine ulaşmışsa, 403 Forbidden hatası döndür
                raise HTTPException(
                    status_code=403, 
                    detail="Alarm limitinize ulaştınız. Daha fazla alarm kurmak için lütfen planınızı yükseltin."
                )

            # 3. Adım: Limit aşılmadıysa, alarmı oluşturma işlemine devam et
            current_price_raw = await fetch_price(alert_in.symbol)
            if current_price_raw is None:
                raise HTTPException(status_code=400, detail=f"Fiyat bulunamadı: {alert_in.symbol}")

            current_price = float(current_price_raw)
            perc = float(alert_in.percentage)

            alert = Alert(
                market=alert_in.market,
                symbol=alert_in.symbol.upper(),
                percentage=perc,
                base_price=current_price,
                upper_limit=current_price * (1 + perc / 100),
                lower_limit=current_price * (1 - perc / 100),
                user_uid=alert_in.user_uid
            )

            session.add(alert)
            session.commit()
            session.refresh(alert)
            return alert
            
    except HTTPException:
        raise # HTTPException'ları tekrar fırlat ki FastAPI doğru yanıtı versin
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/alerts", response_model=List[Alert])
def list_alerts(user_uid: Optional[str] = Query(None)):
      with Session(engine) as session:
        query = select(Alert)
        if user_uid:
            query = query.where(Alert.user_uid == user_uid)
        alerts = session.exec(query).all()
      return alerts

@app.delete("/alerts/{alert_id}")
def delete_alert(alert_id: int, user_uid: str = Query(..., description="The UID of the user deleting the alert")):
    with Session(engine) as session:
        alert = session.get(Alert, alert_id)
        if not alert or alert.user_uid != user_uid:
            raise HTTPException(status_code=404, detail="Alert not found or permission denied")
        session.delete(alert)
        session.commit()
    return {"ok": True}

@app.put("/alerts/{alert_id}", response_model=Alert)
async def edit_alert(alert_id: int, alert_in: AlertCreate): 
    try:
        with Session(engine) as session:
            alert = session.get(Alert, alert_id)
            
            if not alert or alert.user_uid != alert_in.user_uid:
                raise HTTPException(status_code=404, detail="Alert not found or permission denied")

            alert.market = alert_in.market
            alert.symbol = alert_in.symbol.upper()
            alert.percentage = float(alert_in.percentage)
            alert.user_uid = alert_in.user_uid

            current_price_raw = await fetch_price(alert.symbol)
            if current_price_raw is not None:
                current_price = float(current_price_raw)
                alert.base_price = current_price
                alert.upper_limit = current_price * (1 + alert.percentage / 100)
                alert.lower_limit = current_price * (1 - alert.percentage / 100)

            session.add(alert)
            session.commit()
            session.refresh(alert)
            return alert
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/user/settings/{user_uid}", response_model=UserSettings)
def get_user_settings(user_uid: str):
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # If user has no settings saved yet, return default values
            return UserSettings(notifications_enabled=True, language_code="en")
        return UserSettings(notifications_enabled=user.notifications_enabled, language_code=user.language_code)

@app.post("/user/settings/{user_uid}", response_model=User)
def update_user_settings(user_uid: str, settings: UserSettings):
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # If user doesn't exist, create them with ALL settings
            user = User(
                uid=user_uid, 
                notifications_enabled=settings.notifications_enabled,
                language_code=settings.language_code 
            )
            session.add(user)
        else:
            # If user exists, update their settings
            user.notifications_enabled = settings.notifications_enabled
            user.language_code = settings.language_code
            session.add(user)
        
        session.commit()
        session.refresh(user)
        return user

# ----------------------------
# Push Notification
# ----------------------------
def send_push_notification(token: str, title: str, body: str):
    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            
            data={
                "title": title,
                "body": body,
                "click_action": "FLUTTER_NOTIFICATION_CLICK", 
            },
            
            android=messaging.AndroidConfig(
                priority="high",
            ),
            
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        content_available=True,
                    )
                )
            ),
            token=token
        )
        response = messaging.send(message)
        print(f"Push notification sent successfully: {response}")
    except Exception as e:
        print(f"Error sending FCM notification: {e}")
# ----------------------------
# Price Fetch
# ----------------------------
_exchange_rate_cache = {}

async def fetch_price(symbol: str):
    symbol = symbol.upper()
    metals_yf = {"ALTIN": "GC=F", "GÜMÜŞ": "SI=F", "BAKIR": "HG=F"}
    
    if symbol in metals_yf:
        try:
            loop = asyncio.get_event_loop()
            now = datetime.utcnow()
            
            # Dolar/TL kurunu cache'den okumayı dene
            usdtry = None
            if "USDTRY" in _exchange_rate_cache:
                timestamp, rate = _exchange_rate_cache["USDTRY"]
                if (now - timestamp) < timedelta(minutes=60): # 1 saatlik cache
                    usdtry = rate
            
            # Cache'de yoksa veya süresi geçmişse yeniden çek
            if usdtry is None:
                print("Dolar/TL kuru yeniden çekiliyor...")
                usdtry_ticker = await loop.run_in_executor(None, lambda: yf.Ticker("TRY=X"))
                usdtry = usdtry_ticker.history(period="1d", auto_adjust=True)['Close'].iloc[-1]
                _exchange_rate_cache["USDTRY"] = (now, usdtry)

            metal_ticker = await loop.run_in_executor(None, lambda: yf.Ticker(metals_yf[symbol]))
            price_usd = metal_ticker.history(period="1d", auto_adjust=True)['Close'].iloc[-1]
            
            return round((price_usd * usdtry) / 31.1035, 2)
        except Exception as e:
            print(f"Error fetching metal {symbol} with yfinance: {e}")
            return None
        
    # Fonksiyonun geri kalanı aynı...
    if symbol.endswith(".IS") or symbol in BIST_FALLBACK_NAMES:
        try:
            yf_symbol = symbol if symbol.endswith(".IS") else f"{symbol}.IS"
            loop = asyncio.get_event_loop()
            ticker_obj = await loop.run_in_executor(None, lambda: yf.Ticker(yf_symbol))
            price = ticker_obj.history(period="1d", auto_adjust=True)['Close'].iloc[-1]
            return round(float(price), 2)
        except Exception as e:
            print(f"Error fetching BIST {symbol} with yfinance: {e}")
            return None

    async with httpx.AsyncClient(timeout=10) as client:
        if symbol in POPULAR_NASDAQ:
            try:
                r = await client.get(f"{FINNHUB_BASE}/quote", params={"symbol": symbol, "token": FINNHUB_API_KEY})
                r.raise_for_status()
                price = r.json().get("c")
                if price:
                    return round(float(price), 2)
            except Exception as e:
                print(f"Error fetching NASDAQ {symbol} from Finnhub: {e}")
                return None

        if symbol.endswith("USDT"):
            try:
                r = await client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": symbol})
                r.raise_for_status()
                price = float(r.json().get("price", 0))
                if price > 0:
                    return round(price, 2)
            except Exception as e:
                print(f"Error fetching Crypto {symbol} from Binance: {e}")
                return None
        return None
# ----------------------------
# --- YENİ ÇEVİRİ SÖZLÜĞÜ (Metal İsimleri) ---
# ALTIN, GÜMÜŞ, BAKIR sembollerinin farklı dillerdeki karşılıkları.
METAL_LOCALIZATION_MAP = {
    "ALTIN": {
        "tr": "Altın", "en": "Gold", "de": "Gold", "fr": "Or", "es": "Oro",
        "it": "Oro", "ru": "Золото", "zh": "黄金", "hi": "सोना", "ja": "金",
        "ar": "الذهب"
    },
    "GÜMÜŞ": {
        "tr": "Gümüş", "en": "Silver", "de": "Silber", "fr": "Argent", "es": "Plata",
        "it": "Argento", "ru": "Серебро", "zh": "白银", "hi": "चांदी", "ja": "銀",
        "ar": "الفضة"
    },
    "BAKIR": {
        "tr": "Bakır", "en": "Copper", "de": "Kupfer", "fr": "Cuivre", "es": "Cobre",
        "it": "Rame", "ru": "Медь", "zh": "铜", "hi": "तांबा", "ja": "銅",
        "ar": "النحاس"
    }
}
# ----------------------------
# --- YENİ ÇEVİRİ SÖZLÜĞÜ (Şablonlar) ---
# Bu yapıyı dosyanın üst kısımlarına veya price_check_loop'un hemen öncesine ekleyebilirsiniz.
NOTIFICATION_TEMPLATES = {
    "en": {
        "title": "{symbol} Price Alert",
        "body": "The price of {symbol} has {direction} by {percentage}% and is now {price:.2f}.",
        "increased": "increased",
        "decreased": "decreased"
    },
    "tr": {
        "title": "{symbol} Fiyat Alarmı",
        "body": "{symbol} fiyatı %{percentage} {direction} ve {price:.2f} oldu.",
        "increased": "yükseldi",
        "decreased": "düştü"
    },
    "de": {
        "title": "{symbol} Preisalarm",
        "body": "Der Preis von {symbol} ist um {percentage}% {direction} und beträgt jetzt {price:.2f}.",
        "increased": "gestiegen",
        "decreased": "gefallen"
    },
    "fr": {
        "title": "Alerte de Prix {symbol}",
        "body": "Le prix de {symbol} a {direction} de {percentage}% et est maintenant de {price:.2f}.",
        "increased": "augmenté",
        "decreased": "baissé"
    },
    "es": {
        "title": "Alerta de Precio de {symbol}",
        "body": "El precio de {symbol} ha {direction} un {percentage}% y ahora es de {price:.2f}.",
        "increased": "subido",
        "decreased": "bajado"
    },
    "it": {
        "title": "Allarme Prezzo {symbol}",
        "body": "Il prezzo di {symbol} è {direction} del {percentage}% ed è ora di {price:.2f}.",
        "increased": "aumentato",
        "decreased": "diminuito"
    },
    "ru": {
        "title": "Ценовое Оповещение: {symbol}",
        "body": "Цена на {symbol} {direction} на {percentage}% и теперь составляет {price:.2f}.",
        "increased": "выросла",
        "decreased": "упала"
    },
    "zh": {
        "title": "{symbol} 价格提醒",
        "body": "{symbol} 的价格已{direction}{percentage}%，现为 {price:.2f}。",
        "increased": "上涨",
        "decreased": "下跌"
    },
    "hi": {
        "title": "{symbol} मूल्य चेतावनी",
        "body": "{symbol} की कीमत {percentage}% {direction} है और अब {price:.2f} है।",
        "increased": "बढ़ गई",
        "decreased": "घट गई"
    },
    "ja": {
        "title": "{symbol} 価格アラート",
        "body": "{symbol}の価格が{percentage}%{direction}し、現在{price:.2f}です。",
        "increased": "上昇",
        "decreased": "下落"
    },
    "ar": {
        "title": "تنبيه سعر {symbol}",
        "body": "لقد {direction} سعر {symbol} بنسبة {percentage}% وهو الآن {price:.2f}.",
        "increased": "ارتفع",
        "decreased": "انخفض"
    }
}

LANGUAGE_CURRENCY_MAP = {
    'tr': 'TRY',
    'de': 'EUR',
    'fr': 'EUR',
    'es': 'EUR',
    'it': 'EUR',
    'ru': 'RUB',
    'hi': 'INR', 
    'zh': 'CNY', 
    'ja': 'JPY', 
    'ar': 'SAR',
    'en': 'USD', 
}

CURRENCY_TICKERS = {
    "TRY": "TRY=X", 
    "USD": "USD=X",
    "EUR": "EURUSD=X", 
    "RUB": "RUB=X",  
    "JPY": "JPY=X",  
    "CNY": "CNY=X",  
    "INR": "INR=X",  
    "SAR": "SAR=X",  
}
# ----------------------------
# METALS
# ----------------------------
async def get_metals(user_uid: str) -> Dict[str, Optional[float]]:
    try:
        with Session(engine) as session:
            user = session.get(User, user_uid)
            language_code = user.language_code if user and user.language_code else 'en'

        target_currency = LANGUAGE_CURRENCY_MAP.get(language_code, 'USD')

        metal_tickers = {"ALTIN": "GC=F", "GÜMÜŞ": "SI=F", "BAKIR": "HG=F"}
        required_tickers = list(metal_tickers.values())
        
        usd_to_target_rate = 1.0 # Default to USD

        if target_currency != "USD":
            currency_yf_ticker = CURRENCY_TICKERS.get(target_currency)
            if currency_yf_ticker:
                required_tickers.append(currency_yf_ticker)
        
        loop = asyncio.get_event_loop()
        data = await loop.run_in_executor(None, 
            lambda: yf.download(required_tickers, period="1d", progress=False, auto_adjust=True)['Close']
        )

        if data is None or data.empty:
            raise ValueError("yfinance'dan veri alınamadı.")

        # Döviz kurunu al
        if target_currency != "USD" and currency_yf_ticker in data:
            rate = data[currency_yf_ticker].iloc[-1]
            if target_currency == "EUR": # EURUSD=X kuru EUR/USD'dir, bize USD/EUR lazım
                usd_to_target_rate = 1.0 / rate if rate != 0 else 0
            else: # Diğerleri (TRY=X vb.) zaten USD/CURRENCY şeklindedir
                usd_to_target_rate = rate
        
        result = {}
        for name, ticker in metal_tickers.items():
            if ticker in data and not data[ticker].dropna().empty:
                price_usd_ounce = data[ticker].iloc[-1]
                price_target_ounce = price_usd_ounce * usd_to_target_rate
                price_target_gram = price_target_ounce / 31.1035
                result[name] = round(price_target_gram, 2)
            else:
                result[name] = None
        
        return result

    except Exception as e:
        print(f"KRİTİK HATA (get_metals): {e}")
        traceback.print_exc()
        return {"Altın": None, "Gümüş": None, "Bakır": None}

# ----------------------------
# BIST Symbols & Prices
# ----------------------------
BIST100_SYMBOLS = [
    "ASELS.IS","GARAN.IS","THYAO.IS","AKBNK.IS","ISCTR.IS",
    "VESTL.IS","KOZAL.IS","BIMAS.IS","EREGL.IS","PETKM.IS",
    "SISE.IS","KRDMD.IS","YKBNK.IS","FROTO.IS","TOASO.IS",
    "ARCLK.IS","TUPRS.IS","ALARK.IS","MGROS.IS","PGSUS.IS",
    "ENJSA.IS","TCELL.IS","TTKOM.IS","AYGAZ.IS","CCOLA.IS",
    "ODAS.IS","HEKTS.IS","SAHOL.IS","KCHOL.IS","BRSAN.IS",
    "BAGFS.IS","TKFEN.IS","AKSA.IS","BRISA.IS","DOHOL.IS",
    "DOAS.IS","FENER.IS","KARSN.IS","NTHOL.IS","SNGYO.IS",
    "TAVHL.IS","TKNSA.IS","TRGYO.IS","TSPOR.IS","TTRAK.IS",
    "VAKBN.IS","YATAS.IS","ZOREN.IS","AKGRT.IS","BJKAS.IS",
    "NETAS.IS","KOZAA.IS","GOZDE.IS","ALCTL.IS","DMSAS.IS",
    "HALKB.IS","ISGYO.IS","ISDMR.IS","KONYA.IS","LOGO.IS",
    "MAVI.IS","MEPET.IS","OZKGY.IS","PRKME.IS","SASA.IS",
    "SEKUR.IS","SOKM.IS","TMSN.IS","ULKER.IS","YUNSA.IS",
    "ASUZU.IS","EKGYO.IS","KORDS.IS","AKCNS.IS"
][:100]

BIST_FALLBACK_NAMES = {
    "ASELS": "Aselsan",
    "GARAN": "Garanti Bankası",
    "THYAO": "Türk Hava Yolları",
    "AKBNK": "Akbank",
    "ISCTR": "İş Bankası",
    "VESTL": "Vestel",
    "KOZAL": "Koza Altın",
    "BIMAS": "BİM Mağazacılık",
    "EREGL": "Ereğli Demir Çelik",
    "PETKM": "Petkim",
    "SISE": "Şişecam",
    "KRDMD": "Kardemir",
    "YKBNK": "Yapı Kredi Bankası",
    "FROTO": "Ford Otosan",
    "TOASO": "Tofaş",
    "ARCLK": "Arçelik",
    "TUPRS": "Tüpraş",
    "ALARK": "Alarko Holding",
    "MGROS": "Migros",
    "PGSUS": "Pegasus",
    "ENJSA": "Enka İnşaat",
    "TCELL": "Türkcell",
    "TTKOM": "Türk Telekom",
    "AYGAZ": "Aygaz",
    "CCOLA": "Coca Cola İçecek",
    "ODAS": "Odaş Elektrik",
    "HEKTS": "Hektaş",
    "SAHOL": "Sabancı Holding",
    "KCHOL": "Koç Holding",
    "BRSAN": "Brisa",
    "BAGFS": "Bagfas",
    "TKFEN": "Tekfen Holding",
    "AKSA": "Aksa",
    "DOHOL": "Doğan Holding",
    "DOAS": "Doğuş Otomotiv",
    "FENER": "Fenerbahçe Futbol",
    "KARSN": "Karsan",
    "NTHOL": "Netaş",
    "SNGYO": "Sinpas GYO",
    "TAVHL": "TAV Havalimanları",
    "TKNSA": "Teknosa",
    "TRGYO": "Torunlar GYO",
    "TSPOR": "Trabzonspor",
    "TTRAK": "Tümosan Traktör",
    "VAKBN": "Vakıfbank",
    "YATAS": "Yataş",
    "ZOREN": "Zorlu Enerji",
    "AKGRT": "Ak Gıda",
    "BJKAS": "Beşiktaş Futbol",
    "NETAS": "Netaş",
    "KOZAA": "Koza Altın",
    "GOZDE": "Gözde Girişim",
    "ALCTL": "Alcatel-Lucent",
    "DMSAS": "Dimes",
    "HALKB": "Halkbank",
    "ISGYO": "İş GYO",
    "ISDMR": "İş Demir Çelik",
    "KONYA": "Konya Çimento",
    "LOGO": "Logo Yazılım",
    "MAVI": "Mavi Giyim",
    "MEPET": "Mepet",
    "OZKGY": "Özak GYO",
    "PRKME": "Park Elek. Madencilik",
    "SASA": "SASA Polyester",
    "SEKUR": "Sekuro",
    "SOKM": "Şok Marketler",
    "TMSN": "Temsan",
    "ULKER": "Ülker",
    "YUNSA": "Yünsa",
    "ASUZU": "Asuzu",
    "EKGYO": "Emlak Konut GYO",
    "KORDS": "Kordsa",
    "AKCNS": "Akçansa"
}

async def get_bist_symbols_with_name():
    return [{"symbol": s.split(".")[0], "name": BIST_FALLBACK_NAMES.get(s.split(".")[0], s.split(".")[0])}
            for s in BIST100_SYMBOLS]

async def get_bist_prices():
    try:
        data = yf.download(BIST100_SYMBOLS, period="1d", progress=False, auto_adjust=True)['Close']
    except Exception as e:
        print(f"Error downloading BIST data: {e}")
        data = None

    results = []
    for symbol in BIST100_SYMBOLS:
        short_symbol = symbol.split(".")[0]
        price = None
        if data is not None and not data.empty:
            try:
                price_series = data[symbol]
                if not price_series.dropna().empty:
                    price = round(float(price_series.dropna().iloc[-1]), 2)
            except (KeyError, IndexError):
                price = None
        results.append({"symbol": short_symbol, "price": price})
    return results

POPULAR_NASDAQ = [
    "AAPL", "TSLA", "MSFT", "AMZN", "GOOGL", "META", "NVDA", "NFLX", "INTC", "AMD", "ADBE", "CSCO", "CMCSA", "PEP",
    "QCOM", "AVGO", "TXN", "COST", "AMGN", "SBUX", "ISRG", "GILD", "MDLZ", "BIIB", "ZM", "SNPS", "LRCX", "MU",
    "BKNG", "ADSK", "REGN", "VRTX", "EA", "IDXX", "MAR", "CTSH", "KLAC", "ILMN", "ADP", "ROST", "ASML", "DOCU",
    "MELI", "EXC", "ALGN", "FAST", "WDAY", "NTES", "SWKS", "KDP"
]

async def get_nasdaq_symbols_with_name(n=50):
    symbols = POPULAR_NASDAQ[:n]
    results = []
    async with httpx.AsyncClient(timeout=10) as client:
        tasks = [client.get(f"{FINNHUB_BASE}/stock/profile2", params={"symbol": sym, "token": FINNHUB_API_KEY}) for sym in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)

    for sym, r in zip(symbols, responses):
        name = sym
        if not isinstance(r, Exception) and r.status_code == 200:
            data = r.json()
            name = data.get("name") or sym
        results.append({"symbol": sym, "name": name})
    return results

async def get_nasdaq_prices(n=50):
    symbols = POPULAR_NASDAQ[:n]
    async with httpx.AsyncClient(timeout=10) as client:
        tasks = [client.get(f"{FINNHUB_BASE}/quote", params={"symbol": sym, "token": FINNHUB_API_KEY}) for sym in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
    
    results = []
    for sym, r in zip(symbols, responses):
        price = None
        if not isinstance(r, Exception) and r.status_code == 200:
            price_val = r.json().get("c")
            if price_val:
                price = round(price_val, 2)
        results.append({"symbol": sym, "price": price})
    return results

async def get_top_crypto_symbols(n=50):
    url = "https://api.binance.com/api/v3/ticker/price"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(url)
            r.raise_for_status()
            data = r.json()
            symbols = [d["symbol"] for d in data if d["symbol"].endswith("USDT")]
            return symbols[:n]
    except Exception as e:
        print(f"Error fetching crypto symbols: {e}")
        return []

async def get_crypto_prices(n=50):
    symbols = await get_top_crypto_symbols(n)
    async with httpx.AsyncClient(timeout=10) as client:
        tasks = [client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": s}) for s in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
    
    results = []
    for sym, r in zip(symbols, responses):
        if not isinstance(r, Exception) and r.status_code == 200:
            data = r.json()
            price = round(float(data["price"]), 2)
            if price > 0:
                results.append({"symbol": sym[:-4], "price": price}) # USDT son ekini kaldır
    return results

@app.get("/prices")
async def get_all_prices(user_uid: Optional[str] = Query(None)):
    """
    Tüm piyasa fiyatlarını Redis cache'inden okur ve formatlayarak döndürür.
    Bu endpoint, harici API'lere ASLA istek atmaz.
    """
    # 1. Adım: Temel kullanıcı doğrulamasını yap
    if user_uid is None:
        raise HTTPException(status_code=400, detail="Fiyatları çekmek için Kullanıcı ID'si gereklidir.")

    try:
        # 2. Adım: Arka plan görevinin Redis'e yazdığı ana fiyat verisini çek
        cached_prices_json = await redis_conn.get("all_market_prices")
        
        # 3. Adım: Cache'in boş olma durumunu kontrol et (Önemli!)
        # Bu durum, sunucu yeni başladığında ve ilk cron job henüz çalışmadığında yaşanabilir.
        if not cached_prices_json:
            raise HTTPException(
                status_code=503, # Service Unavailable
                detail="Piyasa verileri anlık olarak güncelleniyor, lütfen birkaç saniye sonra tekrar deneyin."
            )

        # 4. Adım: Redis'ten gelen JSON string'ini Python sözlüğüne çevir
        all_prices = json.loads(cached_prices_json)

        # 5. Adım: Düz veriyi, ön yüzün (frontend) beklediği market formatına dönüştür
        # Hızlı arama için sembol listelerinden set'ler oluşturuyoruz.
        bist_symbols_plain = {s.split('.')[0] for s in BIST100_SYMBOLS}
        metals_symbols = {"ALTIN", "GÜMÜŞ", "BAKIR"}
        
        # Her market için boş listeler hazırlıyoruz
        bist_formatted = []
        nasdaq_formatted = []
        crypto_formatted = []
        metals_formatted = []

        # Redis'ten gelen her bir sembolü doğru market listesine ekliyoruz.
        for symbol, price in all_prices.items():
            item = {"symbol": symbol, "price": price}
            if symbol in bist_symbols_plain:
                bist_formatted.append({"market": "BIST", **item})
            elif symbol in POPULAR_NASDAQ:
                nasdaq_formatted.append({"market": "NASDAQ", **item})
            elif symbol in metals_symbols:
                metals_formatted.append({"market": "METALS", **item})
            else: 
                # Diğer marketlere uymayanları Kripto olarak varsayıyoruz.
                crypto_formatted.append({"market": "CRYPTO", **item})
        
        # 6. Adım: Formatlanmış tüm listeleri birleştirip döndür
        return bist_formatted + nasdaq_formatted + crypto_formatted + metals_formatted

    except Exception as e:
        # Beklenmedik bir hata olursa logla ve 500 hatası döndür.
        print(f"KRİTİK HATA (/prices): {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Fiyatlar alınırken bir sunucu hatası oluştu.")
    
@app.get("/symbols_with_name")
async def symbols_with_name(market: str, n: int = 50):
    market = market.upper()
    if market == "BIST":
        return await get_bist_symbols_with_name()
    elif market == "NASDAQ":
        return await get_nasdaq_symbols_with_name(n)
    elif market == "CRYPTO":
        symbols = await get_top_crypto_symbols(n)
        return [{"symbol": s[:-4], "name": s[:-4]} for s in symbols]
    elif market == "METALS":
        return [{"symbol": name, "name": name} for name in ["Altın", "Gümüş", "Bakır"]]
    raise HTTPException(status_code=400, detail="Invalid market specified")
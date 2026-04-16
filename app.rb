require 'sinatra'
require 'stripe'
require 'json'
require "pg"

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# =========================
# POSTGRES
# =========================

def db
  @db ||= PG.connect(ENV["DATABASE_URL"])
end

def init_db
  db.exec("
    CREATE TABLE IF NOT EXISTS clicks (
      id SERIAL PRIMARY KEY,
      count BIGINT NOT NULL DEFAULT 0
    );
  ")

  db.exec("
    CREATE TABLE IF NOT EXISTS payments (
      id SERIAL PRIMARY KEY,
      paid BOOLEAN DEFAULT FALSE
    );
  ")

  # garante linha inicial de clicks
  result = db.exec("SELECT COUNT(*) FROM clicks")
  if result[0]["count"].to_i == 0
    db.exec("INSERT INTO clicks (count) VALUES (0)")
  end
end

init_db

# =========================
# STRIPE WEBHOOK SECRET
# =========================

STRIPE_WEBHOOK_SECRET = ENV['STRIPE_WEBHOOK_SECRET']

# =========================
# CORS
# =========================

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '*' do
  200
end

# =========================
# CLICK LOGIC
# =========================

def get_clicks
  db.exec("SELECT count FROM clicks WHERE id = 1")[0]["count"].to_i
end

def increment_clicks
  db.exec("UPDATE clicks SET count = count + 1 WHERE id = 1")
end

# =========================
# PAYMENT STATUS (REAL)
# =========================

def payment_enabled?
  result = db.exec("SELECT paid FROM payments ORDER BY id DESC LIMIT 1")
  result.ntuples > 0 && result[0]["paid"] == "t"
end

# =========================
# ROUTES
# =========================

get '/' do
  "API online"
end

get '/click-count' do
  content_type :json
  { clicks: get_clicks }.to_json
end

post '/register-click' do
  content_type :json

  if payment_enabled?
    increment_clicks
  end

  { clicks: get_clicks, paid: payment_enabled? }.to_json
end

# =========================
# STRIPE CHECKOUT
# =========================

post '/create-checkout-session' do
  content_type :json

  session = Stripe::Checkout::Session.create(
    mode: 'payment',
    customer_email: 'checkout@clickchallenge.com',
    line_items: [{
      price_data: {
        currency: 'usd',
        unit_amount: 100,
        product_data: {
          name: '1 Dollar Click Challenge'
        }
      },
      quantity: 1
    }],
    success_url: 'https://stripe-click-backend.onrender.com/',
    cancel_url: 'https://stripe-click-backend.onrender.com/'
  )

  { url: session.url }.to_json
end

# =========================
# STRIPE WEBHOOK (REAL TRUTH SOURCE)
# =========================

post '/stripe-webhook' do
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']

  begin
    event = Stripe::Webhook.construct_event(
      payload,
      sig_header,
      STRIPE_WEBHOOK_SECRET
    )
  rescue JSON::ParserError
    status 400
    return
  rescue Stripe::SignatureVerificationError
    status 400
    return
  end

  if event['type'] == 'checkout.session.completed'
    db.exec("INSERT INTO payments (paid) VALUES (true)")
  end

  status 200
end

# =========================
# FRONTEND SUPPORT ENDPOINT
# =========================

get '/status' do
  content_type :json

  result = db.exec("SELECT paid FROM payments ORDER BY id DESC LIMIT 1")

  paid = result.ntuples > 0 && result[0]["paid"] == "t"

  { paid: paid }.to_json
end

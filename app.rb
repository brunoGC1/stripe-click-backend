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

  result = db.exec("SELECT COUNT(*) FROM clicks")

  if result[0]["count"].to_i == 0
    db.exec("INSERT INTO clicks (count) VALUES (0)")
  end
end

init_db

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
# CLICK LOGIC (POSTGRES)
# =========================

def get_clicks
  db.exec("SELECT count FROM clicks WHERE id = 1")[0]["count"].to_i
end

def increment_clicks
  db.exec("UPDATE clicks SET count = count + 1 WHERE id = 1")
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
  increment_clicks
  { clicks: get_clicks }.to_json
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
    success_url: 'https://stripe-click-backend.onrender.com/success?session_id={CHECKOUT_SESSION_ID}',
    cancel_url: 'https://stripe-click-backend.onrender.com/cancel'
  )

  { url: session.url }.to_json
end

# =========================
# STRIPE REDIRECT PAGES
# =========================

get '/success' do
  "Pagamento aprovado! Agora você pode clicar no botão desbloqueado."
end

get '/cancel' do
  "Pagamento cancelado. Tente novamente."
end

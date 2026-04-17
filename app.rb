require 'sinatra'
require 'stripe'
require 'json'
require 'pg'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# =========================
# DATABASE
# =========================
def db
  @db ||= PG.connect(ENV['DATABASE_URL'])
end

configure do
  db.exec <<-SQL
    CREATE TABLE IF NOT EXISTS clicks (
      id SERIAL PRIMARY KEY,
      count INTEGER NOT NULL DEFAULT 0,
      credits INTEGER NOT NULL DEFAULT 0
    );
  SQL

  result = db.exec("SELECT COUNT(*) FROM clicks")

  if result[0]["count"].to_i == 0
    db.exec("INSERT INTO clicks (count, credits) VALUES (0, 1)")
  end
end

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
# STATUS
# =========================
get '/status' do
  content_type :json

  result = db.exec("SELECT * FROM clicks LIMIT 1")

  {
    clicks: result[0]["count"].to_i,
    credits: result[0]["credits"].to_i
  }.to_json
end

# =========================
# CLICK
# =========================
post '/click' do
  content_type :json

  result = db.exec("SELECT * FROM clicks LIMIT 1")
  credits = result[0]["credits"].to_i

  return { ok: false }.to_json if credits <= 0

  db.exec("UPDATE clicks SET count = count + 1, credits = credits - 1")

  updated = db.exec("SELECT * FROM clicks LIMIT 1")

  {
    ok: true,
    clicks: updated[0]["count"].to_i,
    credits: updated[0]["credits"].to_i
  }.to_json
end

# =========================
# STRIPE CHECKOUT
# =========================
post '/create-checkout-session' do
  content_type :json

  session = Stripe::Checkout::Session.create(
    mode: 'payment',
    payment_method_types: ['card'],

    line_items: [{
      price_data: {
        currency: 'usd',
        unit_amount: 100,
        product_data: {
          name: '1 Click Credit'
        }
      },
      quantity: 1
    }],

    customer_creation: 'if_required',
    billing_address_collection: 'auto',

    success_url: 'https://stripe-click-backend.onrender.com/?session_id={CHECKOUT_SESSION_ID}',
    cancel_url: 'https://stripe-click-backend.onrender.com/'
  )

  { url: session.url }.to_json
end

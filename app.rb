require 'sinatra'
require 'stripe'
require 'json'
require 'pg'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# =========================
# ROOT ROUTE
# =========================
get '/' do
  send_file File.join(File.dirname(__FILE__), 'index.html')
end

# =========================
# DB
# =========================
def db
  @db ||= PG.connect(ENV['DATABASE_URL'])
end

configure do
  db.exec <<-SQL
    CREATE TABLE IF NOT EXISTS clicks (
      id SERIAL PRIMARY KEY,
      count INTEGER NOT NULL DEFAULT 0
    );
  SQL

  result = db.exec("SELECT COUNT(*) FROM clicks")
  if result[0]["count"].to_i == 0
    db.exec("INSERT INTO clicks (count) VALUES (0)")
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
# CLICK COUNT
# =========================
get '/click-count' do
  content_type :json

  result = db.exec("SELECT count FROM clicks LIMIT 1")
  { clicks: result[0]["count"].to_i }.to_json
end

post '/register-click' do
  content_type :json

  db.exec("UPDATE clicks SET count = count + 1")

  result = db.exec("SELECT count FROM clicks LIMIT 1")
  { clicks: result[0]["count"].to_i }.to_json
end

# =========================
# STRIPE
# =========================
post '/create-checkout-session' do
  content_type :json

  session = Stripe::Checkout::Session.create(
    mode: 'payment',
    payment_method_types: ['card'],
    customer_creation: 'if_required',

    line_items: [{
      price_data: {
        currency: 'usd',
        unit_amount: 100,
        product_data: {
          name: 'Unlock Click Button'
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
# VERIFY PAYMENT
# =========================
get '/verify-session' do
  content_type :json

  session_id = params[:session_id]

  begin
    session = Stripe::Checkout::Session.retrieve(session_id)

    if session.payment_status == 'paid'
      { paid: true }.to_json
    else
      { paid: false }.to_json
    end
  rescue
    { paid: false }.to_json
  end
end

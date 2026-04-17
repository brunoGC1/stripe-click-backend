require 'sinatra'
require 'stripe'
require 'json'
require 'pg'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

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

    CREATE TABLE IF NOT EXISTS credits (
      id SERIAL PRIMARY KEY,
      balance INTEGER NOT NULL DEFAULT 0
    );
  SQL

  # init rows
  if db.exec("SELECT COUNT(*) FROM clicks")[0]["count"].to_i == 0
    db.exec("INSERT INTO clicks (count) VALUES (0)")
  end

  if db.exec("SELECT COUNT(*) FROM credits")[0]["count"].to_i == 0
    db.exec("INSERT INTO credits (balance) VALUES (0)")
  end
end

# =========================
# ROOT
# =========================
get '/' do
  send_file File.join(File.dirname(__FILE__), 'index.html')
end

# =========================
# GET STATUS (credits + clicks)
# =========================
get '/status' do
  content_type :json

  clicks = db.exec("SELECT count FROM clicks LIMIT 1")[0]["count"].to_i
  credits = db.exec("SELECT balance FROM credits LIMIT 1")[0]["balance"].to_i

  { clicks: clicks, credits: credits }.to_json
end

# =========================
# CLICK (server decides)
# =========================
post '/click' do
  content_type :json

  credit = db.exec("SELECT balance FROM credits LIMIT 1")[0]["balance"].to_i

  if credit <= 0
    return { ok: false, error: "no credits" }.to_json
  end

  # consume credit
  db.exec("UPDATE credits SET balance = balance - 1")

  # add click
  db.exec("UPDATE clicks SET count = count + 1")

  clicks = db.exec("SELECT count FROM clicks LIMIT 1")[0]["count"].to_i
  credits = db.exec("SELECT balance FROM credits LIMIT 1")[0]["balance"].to_i

  { ok: true, clicks: clicks, credits: credits }.to_json
end

# =========================
# STRIPE (BUY CREDIT)
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

    success_url: 'https://stripe-click-backend.onrender.com/?session_id={CHECKOUT_SESSION_ID}',
    cancel_url: 'https://stripe-click-backend.onrender.com/'
  )

  { url: session.url }.to_json
end

# =========================
# VERIFY + ADD CREDIT
# =========================
get '/verify-session' do
  content_type :json

  session_id = params[:session_id]

  begin
    session = Stripe::Checkout::Session.retrieve(session_id)

    if session.payment_status == 'paid'
      db.exec("UPDATE credits SET balance = balance + 1")
      return { paid: true }.to_json
    end

    { paid: false }.to_json
  rescue
    { paid: false }.to_json
  end
end

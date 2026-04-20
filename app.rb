require 'sinatra'
require 'stripe'
require 'json'
require 'pg'

# =========================
# CONFIG STRIPE
# =========================
if ENV['STRIPE_SECRET_KEY'].nil? || ENV['STRIPE_SECRET_KEY'].empty?
  puts "❌ STRIPE_SECRET_KEY NOT SET"
else
  puts "✅ STRIPE KEY LOADED"
end

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# =========================
# SINATRA CONFIG
# =========================
set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

# =========================
# DATABASE
# =========================
def db
  @db ||= PG.connect(ENV['DATABASE_URL'])
end

configure do
  begin
    db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS clicks (
        id SERIAL PRIMARY KEY,
        count INTEGER DEFAULT 0,
        credits INTEGER DEFAULT 0
      );
    SQL

    result = db.exec("SELECT COUNT(*) FROM clicks")

    if result[0]["count"].to_i == 0
      db.exec("INSERT INTO clicks (count, credits) VALUES (0, 0)")
    end
  rescue => e
    puts "DB INIT ERROR: #{e.message}"
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

options "*" do
  200
end

# =========================
# STATUS
# =========================
get '/status' do
  content_type :json

  row = db.exec("SELECT * FROM clicks LIMIT 1")[0]

  {
    clicks: row["count"].to_i,
    credits: row["credits"].to_i
  }.to_json
end

# =========================
# CLICK
# =========================
post '/click' do
  content_type :json

  row = db.exec("SELECT * FROM clicks LIMIT 1")[0]
  credits = row["credits"].to_i

  if credits <= 0
    return { ok: false, clicks: row["count"].to_i, credits: credits }.to_json
  end

  db.exec("UPDATE clicks SET count = count + 1, credits = credits - 1")

  updated = db.exec("SELECT * FROM clicks LIMIT 1")[0]

  {
    ok: true,
    clicks: updated["count"].to_i,
    credits: updated["credits"].to_i
  }.to_json
end

# =========================
# STRIPE CHECKOUT
# =========================
post '/create-checkout-session' do
  content_type :json

  begin
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
      success_url: 'https://brunogc1.github.io/stripe-click-backend/index.html?success=true',
      cancel_url: 'https://brunogc1.github.io/stripe-click-backend/index.html'
    )

    puts "✅ STRIPE SESSION CREATED"

    { url: session.url }.to_json

  rescue => e
    puts "❌ STRIPE ERROR: #{e.message}"
    status 500
    { error: e.message }.to_json
  end
end

# =========================
# WEBHOOK
# =========================
post '/stripe-webhook' do
  payload = request.body.read

  begin
    event = JSON.parse(payload)

    if event['type'] == 'checkout.session.completed'
      db.exec("UPDATE clicks SET credits = credits + 1")
      puts "💰 CREDIT ADDED"
    end

  rescue => e
    puts "WEBHOOK ERROR: #{e.message}"
  end

  status 200
end

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
    db.exec("INSERT INTO clicks (count, credits) VALUES (0, 0)")
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

  row = db.exec("SELECT * FROM clicks LIMIT 1")
  credits = row[0]["credits"].to_i

  return { ok: false, clicks: row[0]["count"].to_i, credits: credits }.to_json if credits <= 0

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

    success_url: 'https://brunogc1.github.io/stripe-click-backend/index.html',
    cancel_url: 'https://brunogc1.github.io/stripe-click-backend/index.html'
  )

  { url: session.url }.to_json
end

# =========================
# WEBHOOK (CORRIGIDO - NÃO DÁ 500)
# =========================
post '/stripe-webhook' do
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']
  endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

  begin
    # ⚠️ se não tiver secret, NÃO quebra o servidor
    if endpoint_secret.nil? || endpoint_secret.empty?
      puts "⚠️ STRIPE_WEBHOOK_SECRET NÃO CONFIGURADO"
      status 200
      return
    end

    event = Stripe::Webhook.construct_event(
      payload,
      sig_header,
      endpoint_secret
    )

    puts "EVENTO RECEBIDO: #{event['type']}"

    if event['type'] == 'checkout.session.completed'
      db.exec("UPDATE clicks SET credits = credits + 1")
      puts "💰 CREDIT ADDED"
    end

  rescue JSON::ParserError => e
    puts "JSON ERROR: #{e.message}"
    status 400
    return
  rescue Stripe::SignatureVerificationError => e
    puts "SIGNATURE ERROR: #{e.message}"
    status 400
    return
  rescue => e
    puts "UNKNOWN ERROR: #{e.message}"
    status 500
    return
  end

  status 200
end

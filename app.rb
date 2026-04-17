require 'sinatra'
require 'json'

# ⚠️ evita crash silencioso de libs externas
begin
  require 'stripe'
rescue
  puts "Stripe gem not loaded"
end

begin
  require 'pg'
rescue
  puts "PG gem not loaded"
end

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

# =========================
# SAFE DB (não crasha server)
# =========================
def db
  return @db if @db

  begin
    @db = PG.connect(ENV['DATABASE_URL'])
  rescue => e
    puts "DB ERROR: #{e.message}"
    @db = nil
  end
end

# =========================
# INIT SAFE TABLE
# =========================
configure do
  begin
    if db
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
  rescue => e
    puts "INIT ERROR: #{e.message}"
  end
end

# =========================
# STATUS (NUNCA CRASHA)
# =========================
get '/status' do
  content_type :json

  begin
    row = db&.exec("SELECT * FROM clicks LIMIT 1")&.first

    return { clicks: 0, credits: 0 }.to_json unless row

    {
      clicks: row["count"].to_i,
      credits: row["credits"].to_i
    }.to_json
  rescue => e
    puts "STATUS ERROR: #{e.message}"
    { clicks: 0, credits: 0 }.to_json
  end
end

# =========================
# CLICK SAFE
# =========================
post '/click' do
  content_type :json

  begin
    row = db&.exec("SELECT * FROM clicks LIMIT 1")&.first

    return { ok: false, clicks: 0, credits: 0 }.to_json unless row

    credits = row["credits"].to_i

    return { ok: false, clicks: row["count"].to_i, credits: 0 }.to_json if credits <= 0

    db.exec("UPDATE clicks SET count = count + 1, credits = credits - 1")

    updated = db.exec("SELECT * FROM clicks LIMIT 1")[0]

    {
      ok: true,
      clicks: updated["count"].to_i,
      credits: updated["credits"].to_i
    }.to_json

  rescue => e
    puts "CLICK ERROR: #{e.message}"
    { ok: false, clicks: 0, credits: 0 }.to_json
  end
end

# =========================
# CHECKOUT SAFE (SEM CRASH POSSÍVEL)
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
          product_data: { name: '1 Click Credit' }
        },
        quantity: 1
      }],
      success_url: 'https://brunogc1.github.io/stripe-click-backend/index.html',
      cancel_url: 'https://brunogc1.github.io/stripe-click-backend/index.html'
    )

    { url: session.url }.to_json

  rescue => e
    puts "CHECKOUT ERROR: #{e.message}"
    { error: "checkout failed" }.to_json
  end
end

# =========================
# WEBHOOK (AGORA 100% NÃO CRASHA)
# =========================
post '/stripe-webhook' do
  begin
    payload = request.body.read

    puts "🔥 WEBHOOK RECEBIDO"

    begin
      event = JSON.parse(payload)
    rescue
      puts "INVALID JSON"
      status 200
      return
    end

    if event['type'] == 'checkout.session.completed'
      begin
        if db
          db.exec("UPDATE clicks SET credits = credits + 1")
          puts "💰 CREDIT ADDED"
        end
      rescue => e
        puts "DB ERROR WEBHOOK: #{e.message}"
      end
    end

  rescue => e
    puts "WEBHOOK FATAL SAFE: #{e.message}"
  end

  # 🔥 SEMPRE OK PRO STRIPE
  status 200
end

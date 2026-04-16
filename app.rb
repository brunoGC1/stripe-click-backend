require 'sinatra'
require 'stripe'
require 'json'
require 'pg'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# conexão com Postgres (Render)
def db
  @db ||= PG.connect(ENV['DATABASE_URL'])
end

# cria tabela se não existir
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

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '*' do
  200
end

# 🔢 pegar contador global
get '/click-count' do
  content_type :json

  result = db.exec("SELECT count FROM clicks LIMIT 1")
  { clicks: result[0]["count"].to_i }.to_json
end

# 🔥 incrementa clique (somente após desbloqueio no frontend)
post '/register-click' do
  content_type :json

  db.exec("UPDATE clicks SET count = count + 1")

  result = db.exec("SELECT count FROM clicks LIMIT 1")
  { clicks: result[0]["count"].to_i }.to_json
end

# 💳 Stripe checkout
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
          name: 'Unlock Click Button'
        }
      },
      quantity: 1
    }],
    success_url: 'https://brunogc1.github.io/stripe-click-backend/?success=true',
    cancel_url: 'https://brunogc1.github.io/stripe-click-backend/?canceled=true'
  )

  { url: session.url }.to_json
end

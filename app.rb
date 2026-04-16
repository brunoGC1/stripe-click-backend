require 'sinatra'
require 'stripe'
require 'json'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '/create-checkout-session' do
  200
end

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
    success_url: 'https://stripe-click-backend.vercel.app/?success=true',
    cancel_url: 'https://stripe-click-backend.vercel.app/?cancel=true'
  )

  { url: session.url }.to_json
end

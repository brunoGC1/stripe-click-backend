require 'sinatra'
require 'stripe'
require 'json'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 3000)

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

post '/create-checkout-session' do
  content_type :json

  session = Stripe::Checkout::Session.create(
    mode: 'payment',
    line_items: [{
      price_data: {
        currency: 'usd',
        unit_amount: 100,
        product_data: {
          name: 'Button Click - $1'
        }
      },
      quantity: 1
    }],
    success_url: "#{ENV['BASE_URL']}/success",
    cancel_url: "#{ENV['BASE_URL']}/cancel"
  )

  { url: session.url }.to_json
end

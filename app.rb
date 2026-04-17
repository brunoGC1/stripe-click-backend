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

      # =========================
      # MENOS FRICÇÃO POSSÍVEL
      # =========================
      customer_creation: 'if_required',
      billing_address_collection: 'auto',

      # NÃO força email manualmente
      # (Stripe decide quando precisa)

      success_url: 'https://stripe-click-backend.onrender.com/?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: 'https://stripe-click-backend.onrender.com/'
    )

    { url: session.url }.to_json

  rescue => e
    puts "Stripe error: #{e.message}"
    { error: e.message }.to_json
  end
end

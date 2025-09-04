# frozen_string_literal: true

require "spec_helper"
require "shared_examples/authorize_called"

describe PublicController do
  render_views

  let!(:demo_product) { create(:product, unique_permalink: "demo") }

  { api: "API",
    ping: "Ping",
    widgets: "Widgets" }.each do |url, title|
    describe "GET '#{url}'" do
      it "succeeds and set instance variable" do
        get(url)
        expect(assigns(:title)).to eq(title)
        expect(assigns(:"on_#{url}_page")).to be(true)
      end
    end
  end

  describe "GET home" do
    context "when not authenticated" do
      it "redirects to the login page" do
        get :home

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before do
        sign_in create(:user)
      end

      it "redirects to the dashboard page" do
        get :home

        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  describe "GET widgets" do
    context "with user signed in as admin for seller" do
      let(:seller) { create(:named_seller) }

      include_context "with user signed in as admin for seller"

      it "initializes WidgetPresenter with seller" do
        get :widgets

        expect(response).to be_successful
        expect(assigns[:widget_presenter].seller).to eq(seller)
      end
    end
  end

  describe "POST charge_data" do
    it "returns correct information if no purchases match" do
      get :charge_data, params: { last_4: "4242", email: "edgar@gumroad.com" }
      expect(response.parsed_body["success"]).to be(false)
    end

    it "returns correct information if a purchase matches" do
      create(:purchase, price_cents: 100, fee_cents: 30, card_visual: "**** 4242", email: "edgar@gumroad.com")
      get :charge_data, params: { last_4: "4242", email: "edgar@gumroad.com" }
      expect(response.parsed_body["success"]).to be(true)
    end

    it "returns only the successful and gift_receiver_purchase_successful purchases that match the criteria" do
      mail_double = double
      allow(mail_double).to receive(:deliver_later)

      purchase = create(:purchase, price_cents: 100, fee_cents: 30, card_visual: "**** 4242", email: "edgar@gumroad.com")
      create(:purchase, purchase_state: "preorder_authorization_successful", price_cents: 100, fee_cents: 30, card_visual: "**** 4242", email: "edgar@gumroad.com")
      gift_receiver_purchase = create(:purchase, purchase_state: "gift_receiver_purchase_successful", price_cents: 100, fee_cents: 30, card_visual: "**** 4242", email: "edgar@gumroad.com")
      create(:purchase, purchase_state: "failed", price_cents: 100, fee_cents: 30, card_visual: "**** 4242", email: "edgar@gumroad.com")

      expect(CustomerMailer).to receive(:grouped_receipt).with([purchase.id, gift_receiver_purchase.id]).and_return(mail_double)
      get :charge_data, params: { last_4: "4242", email: "edgar@gumroad.com" }
      expect(response.parsed_body["success"]).to be(true)
    end
  end

  describe "paypal_charge_data" do
    context "when there is no invoice_id value passed" do
      let(:params) { { invoice_id: nil } }

      it "returns false" do
        get(:paypal_charge_data, params:)
        expect(response.parsed_body["success"]).to be(false)
        expect(SendPurchaseReceiptJob.jobs.size).to eq(0)
      end
    end

    context "with a valid invoice_id value" do
      let(:purchase) { create(:purchase, price_cents: 100, fee_cents: 30) }
      let(:params) { { invoice_id: purchase.external_id } }

      it "returns correct information and enqueues job for sending the receipt" do
        get(:paypal_charge_data, params:)
        expect(response.parsed_body["success"]).to be(true)
        expect(SendPurchaseReceiptJob).to have_enqueued_sidekiq_job(purchase.id).on("critical")
      end

      context "when the product has stampable PDFs" do
        before do
          allow_any_instance_of(Link).to receive(:has_stampable_pdfs?).and_return(true)
        end

        it "enqueues job for sending the receipt on the default queue" do
          get(:paypal_charge_data, params:)
          expect(SendPurchaseReceiptJob).to have_enqueued_sidekiq_job(purchase.id).on("default")
        end
      end
    end
  end

  describe "GET new_ticket" do
    it "succeeds and sets title and reCAPTCHA site key when feature flag enabled" do
      Feature.activate(:public_support_tickets_enabled)
      allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_site_key")

      get :new_ticket

      expect(response).to be_successful
      expect(assigns(:title)).to eq("Contact Support")
      expect(assigns(:recaptcha_site_key)).to eq("test_site_key")
    end

    it "returns 404 when feature flag disabled" do
      Feature.deactivate(:public_support_tickets_enabled)

      get :new_ticket

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create_ticket" do
    let!(:user) { create(:user, email: "test@example.com") }

    context "with valid parameters" do
      let(:valid_params) do
        {
          email: "test@example.com",
          subject: "Test Subject",
          message: "Test message content"
        }
      end

      before do
        Feature.activate(:public_support_tickets_enabled)
        allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_site_key")
        allow_any_instance_of(PublicController).to receive(:valid_recaptcha_response?).and_return(true)
      end

      it "creates a support ticket successfully" do
        allow_any_instance_of(PublicSupportTicketCreationService).to receive(:call).and_return({
                                                                                                 success: true,
                                                                                                 ticket_id: "ticket_123"
                                                                                               })

        post :create_ticket, params: valid_params

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["ticket_id"]).to eq("ticket_123")
      end

      it "redirects to confirmation page on success" do
        allow_any_instance_of(PublicSupportTicketCreationService).to receive(:call).and_return({
                                                                                                 success: true,
                                                                                                 ticket_id: "ticket_123"
                                                                                               })

        post :create_ticket, params: valid_params

        expect(response.parsed_body["redirect_url"]).to include("/support/tickets/ticket_123/confirmation")
      end
    end

    context "with invalid email" do
      it "returns error for non-existent user" do
        Feature.activate(:public_support_tickets_enabled)
        allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_site_key")
        allow_any_instance_of(PublicController).to receive(:valid_recaptcha_response?).and_return(true)

        post :create_ticket, params: {
          email: "nonexistent@example.com",
          subject: "Test Subject",
          message: "Test message"
        }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["error_message"]).to eq("Please check your email address and try again.")
      end
    end

    context "with missing required fields" do
      it "returns error when email is blank" do
        Feature.activate(:public_support_tickets_enabled)
        allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_site_key")
        allow_any_instance_of(PublicController).to receive(:valid_recaptcha_response?).and_return(true)

        post :create_ticket, params: {
          email: "",
          subject: "Test Subject",
          message: "Test message"
        }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["error_message"]).to eq("Please fill in all required fields.")
      end
    end

    context "with failed reCAPTCHA" do
      it "returns error when reCAPTCHA validation fails" do
        Feature.activate(:public_support_tickets_enabled)
        allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_site_key")
        allow_any_instance_of(PublicController).to receive(:valid_recaptcha_response?).and_return(false)

        post :create_ticket, params: {
          email: "test@example.com",
          subject: "Test Subject",
          message: "Test message"
        }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["error_message"]).to include("verify the CAPTCHA")
      end
    end
  end

  describe "GET ticket_confirmation" do
    it "succeeds and sets instance variables" do
      Feature.activate(:public_support_tickets_enabled)
      allow(GlobalConfig).to receive(:get).with("HELPER_WIDGET_HOST").and_return("https://test-helper.dev")
      allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_key")
      get :ticket_confirmation, params: { id: "ticket_123" }

      expect(response).to be_successful
      expect(assigns(:title)).to eq("Support Ticket Submitted")
      expect(assigns(:ticket_id)).to eq("ticket_123")
      expect(assigns(:expected_response_time)).to eq("24 hours")
      expect(assigns(:description)).to eq("Your support ticket has been submitted successfully")
    end
  end

  describe "GET customer_info" do
    let!(:user) { create(:user, email: "test@example.com", name: "Test User") }

    context "with valid email parameter" do
      it "returns customer info for existing user" do
        Feature.activate(:public_support_tickets_enabled)
        get :customer_info, params: { email: "test@example.com" }

        expect(response).to be_successful
        customer_info = response.parsed_body
        expect(customer_info["name"]).to eq("Test User")
        expect(customer_info["metadata"]["source"]).to eq("existing_user_support_ticket")
      end

      it "returns empty info for non-existing user" do
        Feature.activate(:public_support_tickets_enabled)
        get :customer_info, params: { email: "nonexistent@example.com" }

        expect(response).to be_successful
        customer_info = response.parsed_body
        expect(customer_info["name"]).to be_nil
        expect(customer_info["metadata"]).to eq({})
      end
    end

    context "without email parameter" do
      it "returns bad request error" do
        Feature.activate(:public_support_tickets_enabled)
        get :customer_info

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq("Email parameter is required")
      end
    end
  end
end

# frozen_string_literal: true

class PublicController < ApplicationController
  include ActionView::Helpers::NumberHelper
  include HelperWidget

  before_action { opt_out_of_header(:csp) } # for the use of external JS on public pages

  before_action :hide_layouts, only: [:thank_you]
  before_action :set_on_public_page

  def home
    redirect_to user_signed_in? ? after_sign_in_path_for(logged_in_user) : login_path
  end

  def widgets
    @on_widgets_page = true
    @title = "Widgets"
    @widget_presenter = WidgetPresenter.new(seller: current_seller)
  end

  def charge
    @title = "Why is there a charge on my account?"
  end

  def charge_data
    purchases = Purchase.successful_gift_or_nongift.where("email = ?", params[:email])
    purchases = purchases.where("card_visual like ?", "%#{params[:last_4]}%") if params[:last_4].present? && params[:last_4].length == 4
    if purchases.none?
      render json: { success: false }
    else
      CustomerMailer.grouped_receipt(purchases.ids).deliver_later(queue: "critical")
      render json: { success: true }
    end
  end

  def paypal_charge_data
    return render json: { success: false } if params[:invoice_id].nil?

    purchase = Purchase.find_by_external_id(params[:invoice_id])
    if purchase.nil?
      render json: { success: false }
    else
      SendPurchaseReceiptJob.set(queue: purchase.link.has_stampable_pdfs? ? "default" : "critical").perform_async(purchase.id)
      render json: { success: true }
    end
  end

  def license_key_lookup
    @title = "What is my license key?"
  end

  # api methods

  def api
    @title = "API"
    @on_api_page = true
  end

  def ping
    @title = "Ping"
    @on_ping_page = true
  end

  def thank_you
    @title = "Thank you!"
  end

  def working_webhook
    render plain: "http://www.gumroad.com"
  end

  def crossdomain
    respond_to :xml
  end

    # public support portal actions
    def new_ticket
      @title = "Contact Support"
      @recaptcha_site_key = GlobalConfig.get("RECAPTCHA_SIGNUP_SITE_KEY")
    end

    def create_ticket
      # Validate reCAPTCHA
      site_key = GlobalConfig.get("RECAPTCHA_SIGNUP_SITE_KEY")
      if !(Rails.env.development? && GOOGLE_CLOUD_PROJECT_ID.blank?) && !valid_recaptcha_response?(site_key: site_key)
        return render json: {
          success: false,
          error_message: "Sorry, we could not verify the CAPTCHA. Please try again."
        }
      end

      # Validate required parameters
      email = params[:email]&.strip
      subject = params[:subject]&.strip
      message = params[:message]&.strip

      if email.blank? || subject.blank? || message.blank?
        return render json: {
          success: false,
          error_message: "Please fill in all required fields."
        }
      end

               # Validate email format
         unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
           return render json: {
             success: false,
             error_message: "Please enter a valid email address."
           }
         end

         # Check if user exists - only allow existing Gumroad users to create tickets
         user = User.find_by(email: email)
         unless user
           return render json: {
             success: false,
             error_message: "Please check your email address and try again."
           }
         end

         begin
           # Create Helper conversation using the service
           result = PublicSupportTicketCreationService.new(
             email: email,
             subject: subject,
             message: message
           ).call

        if result[:success]
          Rails.logger.info("Public support ticket created: #{result[:ticket_id]} for #{email}")
          render json: {
            success: true,
            ticket_id: result[:ticket_id],
            redirect_url: support_ticket_confirmation_path(result[:ticket_id])
          }
        else
          Rails.logger.error("Failed to create public support ticket: #{result[:error]}")
          render json: {
            success: false,
            error_message: "Sorry, we couldn't create your support ticket. Please try again."
          }
        end
      rescue => e
        Rails.logger.error("Error creating public support ticket: #{e.message}")
        render json: {
          success: false,
          error_message: "Sorry, something went wrong. Please try again."
        }
      end
    end

    def ticket_confirmation
      @title = "Support Ticket Submitted"
      @ticket_id = params[:id]
      @expected_response_time = "24 hours"
      @description = "Your support ticket has been submitted successfully"
      @canonical_url = support_ticket_confirmation_url(@ticket_id)

      render layout: "help_center"
    end


  # API endpoint for Helper to fetch customer information for existing users
  def customer_info
    email = params[:email]
    if email.blank?
      render json: { error: "Email parameter is required" }, status: :bad_request
      return
    end

    # Only provide info for existing Gumroad users - return consistent response to prevent email enumeration
    user = User.find_by(email: email)
    if user
      customer_info = {
        name: user.name.presence,
        metadata: {
          source: "existing_user_support_ticket",
          submitted_at: Time.current.iso8601,
          user_id: user.id,
          registered_at: user.created_at.iso8601
        }
      }
      render json: customer_info
    else
      # Return empty customer info for non-existing users to prevent email enumeration
      render json: { name: nil, metadata: {} }
    end
  end

  private
    def set_on_public_page
      @body_class = "public"
    end
end

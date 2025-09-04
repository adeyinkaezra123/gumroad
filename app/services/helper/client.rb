# frozen_string_literal: true

# frozen_string_literal: truennrequire 'jwt'

##
# Collection of methods to use Helper API.
##

class Helper::Client
  include HTTParty

  base_uri "https://api.helper.ai"

  HELPER_MAILBOX_SLUG = "gumroad"

  def create_hmac_digest(params: nil, json: nil)
    if (params.present? && json.present?) || (params.nil? && json.nil?)
      raise "Either params or json must be provided, but not both"
    end

    serialized_params = json ? json.to_json : params.to_query
    OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), GlobalConfig.get("HELPER_SECRET_KEY"), serialized_params)
  end

  def add_note(conversation_id:, message:)
    params = { message:, timestamp: }
    headers = get_auth_headers(json: params)
    response = self.class.post("/api/v1/mailboxes/#{HELPER_MAILBOX_SLUG}/conversations/#{conversation_id}/notes/", headers:, body: params.to_json)

    Bugsnag.notify("Helper error: could not add note", conversation_id:, message:) unless response.success?

    response.success?
  end

  def send_reply(conversation_id:, message:, draft: false, response_to: nil)
    params = { message:, response_to:, draft:, timestamp: }
    headers = get_auth_headers(json: params)
    response = self.class.post("/api/v1/mailboxes/#{HELPER_MAILBOX_SLUG}/conversations/#{conversation_id}/emails/", headers:, body: params.to_json)

    Bugsnag.notify("Helper error: could not send reply", conversation_id:, message:) unless response.success?

    response.success?
  end

  def create_conversation_for_unauthenticated_user(email:, subject:, message:)
    # Create anonymous widget session with consistent session ID
    anonymous_session_id = SecureRandom.uuid
    widget_session = create_anonymous_widget_session(email, anonymous_session_id, subject)
    return { success: false, error: "Failed to create widget session" } unless widget_session

    # Create conversation using Helper API
    conversation_result = create_helper_conversation(widget_session, subject)
    return conversation_result unless conversation_result[:success]

    # Create initial message in the conversation using the same session
    message_result = create_helper_message(widget_session, conversation_result[:conversation_slug], message, subject)
    return message_result unless message_result[:success]

    {
      success: true,
      conversation_id: conversation_result[:conversation_slug],
      conversation_slug: conversation_result[:conversation_slug]
    }
  end

  def close_conversation(conversation_id:)
    params = { status: "closed", timestamp: }
    headers = get_auth_headers(json: params)
    response = self.class.patch("/api/v1/mailboxes/#{HELPER_MAILBOX_SLUG}/conversations/#{conversation_id}/", headers:, body: params.to_json)

    Bugsnag.notify("Helper error: could not close conversation", conversation_id:) unless response.success?

    response.success?
  end

  private
    def get_auth_headers(params: nil, json: nil)
      hmac_base64 = Base64.encode64(create_hmac_digest(params:, json:))
      {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{hmac_base64}"
      }
    end

    def timestamp
      DateTime.current.to_i
    end

    def create_anonymous_widget_session(email, anonymous_session_id, subject = nil)
      timestamp = (Time.current.to_f * 1000).to_i
      email_hash = helper_widget_email_hmac(email, timestamp)

      {
        email: email,
        emailHash: email_hash,
        timestamp: timestamp,
        showWidget: true,
        isAnonymous: true,
        isWhitelabel: false,
        title: "Gumroad Support",
        anonymousSessionId: anonymous_session_id,
        subject: subject
      }
    end

    def create_helper_conversation(widget_session, subject)
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{create_widget_jwt_token(widget_session)}"
      }

      # Include customerInfoUrl for existing users
      customer_info_url = if widget_session[:email]
        Rails.application.routes.url_helpers.customer_info_path(
          email: widget_session[:email],
          host: GlobalConfig.get("HELPER_WIDGET_HOST") || "https://helperai.dev"
        )
      else
        nil
      end

      body = {
        subject: subject || "Support Request",
        isPrompt: false,
        customerInfoUrl: customer_info_url
      }

      response = self.class.post("#{helper_widget_host}/api/chat/conversation", headers:, body: body.to_json)

      unless response.success?
        Bugsnag.notify("Helper error: could not create conversation", subject:, response: response.body)
        return { success: false, error: "Failed to create conversation" }
      end

      {
        success: true,
        conversation_slug: response.parsed_response["conversationSlug"]
      }
    end

    def create_helper_message(widget_session, conversation_slug, message, subject = nil)
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{create_widget_jwt_token(widget_session)}"
      }

      # For existing users, include customer info URL so Helper can fetch detailed info
      customer_info_url = if widget_session[:email]
        Rails.application.routes.url_helpers.customer_info_path(
          email: widget_session[:email],
          host: GlobalConfig.get("HELPER_WIDGET_HOST") || "https://helperai.dev"
        )
      else
        nil
      end

      body = {
        content: message,
        attachments: [],
        tools: {},
        customerSpecificTools: false,
        customerInfoUrl: customer_info_url
      }

      response = self.class.post("#{helper_widget_host}/api/chat/conversation/#{conversation_slug}/message", headers:, body: body.to_json)

      unless response.success?
        Bugsnag.notify("Helper error: could not create message", conversation_slug:, message:, response: response.body)
        return { success: false, error: "Failed to create message" }
      end

      {
        success: true,
        message_id: response.parsed_response["messageId"]
      }
    end

    def helper_widget_email_hmac(email, timestamp)
      message = "#{email}:#{timestamp}"
      OpenSSL::HMAC.hexdigest(
        "sha256",
        GlobalConfig.get("HELPER_WIDGET_SECRET"),
        message
      )
    end

    def create_widget_jwt_token(widget_session)
      JWT.encode(
        {
          email: widget_session[:email],
          showWidget: widget_session[:showWidget],
          isWhitelabel: widget_session[:isWhitelabel],
          title: widget_session[:title],
          isAnonymous: widget_session[:isAnonymous],
          anonymousSessionId: widget_session[:anonymousSessionId]
        },
        GlobalConfig.get("HELPER_WIDGET_SECRET"),
        "HS256"
      )
    end

    def helper_widget_host
      GlobalConfig.get("HELPER_WIDGET_HOST")
    end
end

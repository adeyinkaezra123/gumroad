# frozen_string_literal: true

##
# Service to create public support tickets by creating Helper conversations
# for existing Gumroad users (who may not be authenticated)
##

class PublicSupportTicketCreationService
  def initialize(email:, subject:, message:)
    @email = email
    @subject = subject
    @message = message
  end

  def call
    result = create_helper_conversation

    if result[:success]
      {
        success: true,
        ticket_id: result[:conversation_id],
        conversation_slug: result[:conversation_slug]
      }
    else
      {
        success: false,
        error: result[:error] || "Failed to create support ticket"
      }
    end
  end

  private

    attr_reader :email, :subject, :message

    def create_helper_conversation
      # Use the anonymous method for now - we'll handle customer info properly
      helper_client.create_conversation_for_unauthenticated_user(
        email: email,
        subject: subject,
        message: message
      )
    end

    def existing_user?
      User.exists?(email: email)
    end

    def helper_client
      @helper_client ||= Helper::Client.new
    end
end

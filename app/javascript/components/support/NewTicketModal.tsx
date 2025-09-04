import React from "react";

import FileUtils from "$app/utils/file";

import { Button } from "$app/components/Button";
import { FileRowContent } from "$app/components/FileRowContent";
import { Icon } from "$app/components/Icons";
import { Modal } from "$app/components/Modal";
import { showAlert } from "$app/components/server-components/Alert";
import { RecaptchaCancelledError, useRecaptcha } from "$app/components/useRecaptcha";

// Conditional import to avoid SSR issues
let useCreateConversation: any, useCreateMessage: any;
if (typeof window !== "undefined") {
  try {
    const helperHooks = require("@helperai/react");
    useCreateConversation = helperHooks.useCreateConversation;
    useCreateMessage = helperHooks.useCreateMessage;
  } catch {
    // Helper hooks not available
  }
}

export function NewTicketModal({
  open,
  onClose,
  onCreated,
  isUnauthenticated = false,
  recaptchaSiteKey = null,
}: {
  open: boolean;
  onClose: () => void;
  onCreated: (slug: string) => void;
  isUnauthenticated?: boolean;
  recaptchaSiteKey?: string | null;
}) {
  // Only use Helper hooks when available and not unauthenticated
  const createConversation = React.useMemo(() => {
    if (!useCreateConversation || isUnauthenticated) return null;
    try {
      const { mutateAsync } = useCreateConversation({
        onError: (error: any) => {
          showAlert(error.message, "error");
        },
      });
      return mutateAsync;
    } catch {
      return null;
    }
  }, [isUnauthenticated]);

  const createMessage = React.useMemo(() => {
    if (!useCreateMessage || isUnauthenticated) return null;
    try {
      const { mutateAsync } = useCreateMessage({
        onError: (error: any) => {
          showAlert(error.message, "error");
        },
      });
      return mutateAsync;
    } catch {
      return null;
    }
  }, [isUnauthenticated]);

  const [email, setEmail] = React.useState("");
  const [subject, setSubject] = React.useState("");
  const [message, setMessage] = React.useState("");
  const [attachments, setAttachments] = React.useState<File[]>([]);
  const [isSubmitting, setIsSubmitting] = React.useState(false);
  const formRef = React.useRef<HTMLFormElement | null>(null);
  const fileInputRef = React.useRef<HTMLInputElement | null>(null);

  // Initialize reCAPTCHA for unauthenticated users
  const recaptcha = useRecaptcha({ siteKey: isUnauthenticated ? recaptchaSiteKey : null });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (isUnauthenticated) {
      // Handle unauthenticated submission
      if (!email.trim() || !subject.trim() || !message.trim()) {
        showAlert("Please fill in all required fields.", "error");
        return;
      }

      // Basic email validation
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email.trim())) {
        showAlert("Please enter a valid email address.", "error");
        return;
      }

      setIsSubmitting(true);

      try {
        const formData = new FormData();
        formData.append("email", email.trim());
        formData.append("subject", subject.trim());
        formData.append("message", message.trim());

        // Execute reCAPTCHA for unauthenticated users
        let recaptchaToken = null;
        if (recaptchaSiteKey) {
          try {
            recaptchaToken = await recaptcha.execute();
          } catch (error) {
            if (error instanceof RecaptchaCancelledError) {
              showAlert("Please complete the CAPTCHA verification.", "error");
              return;
            } else {
              showAlert("CAPTCHA verification failed. Please try again.", "error");
              return;
            }
          }
        }
        if (recaptchaToken) {
          formData.append("g-recaptcha-response", recaptchaToken);
        }

        const response = await fetch("/support/tickets", {
          method: "POST",
          body: formData,
          headers: {
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || "",
          },
        });

        const data = await response.json();

        if (data.success) {
          onCreated(data.ticket_id);
          // Reset form
          setEmail("");
          setSubject("");
          setMessage("");
          onClose();
          // Redirect to confirmation page
          window.location.href = data.redirect_url;
        } else {
          showAlert(data.error_message || "Something went wrong. Please try again.", "error");
        }
      } catch (error) {
        showAlert("Network error. Please check your connection and try again.", "error");
      } finally {
        setIsSubmitting(false);
      }
    } else {
      // Handle authenticated submission (existing Helper flow)
      if (!subject.trim() || !message.trim()) return;

      if (!createConversation || !createMessage) {
        showAlert("Helper service is not available. Please try again later.", "error");
        return;
      }

      setIsSubmitting(true);
      try {
        const { conversationSlug } = await createConversation({ subject: subject.trim() });
        await createMessage({ conversationSlug, content: message.trim(), attachments });
        onCreated(conversationSlug);
      } finally {
        setIsSubmitting(false);
      }
    }
  };

  const isFormValid = isUnauthenticated
    ? email.trim() && subject.trim() && message.trim()
    : subject.trim() && message.trim();

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isUnauthenticated ? "Contact Support" : "How can we help you today?"}
      footer={
        <>
          {!isUnauthenticated && (
            <Button onClick={() => fileInputRef.current?.click()} disabled={isSubmitting}>
              <Icon name="paperclip" /> Attach files
            </Button>
          )}
          <Button
            color="accent"
            onClick={() => formRef.current?.requestSubmit()}
            disabled={isSubmitting || !isFormValid}
          >
            {isSubmitting ? "Sending..." : "Send message"}
          </Button>
        </>
      }
    >
      <form ref={formRef} className="space-y-4 md:w-[700px]" onSubmit={handleSubmit}>
        {isUnauthenticated && (
          <>
            <label className="sr-only">Email</label>
            <input
              type="email"
              value={email}
              placeholder="Your email address"
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </>
        )}
        <label className="sr-only">Subject</label>
        <input value={subject} placeholder="Subject" onChange={(e) => setSubject(e.target.value)} />
        <label className="sr-only">Message</label>
        <textarea
          rows={6}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder="Tell us about your issue or question..."
        />
        {!isUnauthenticated && (
          <input
            ref={fileInputRef}
            type="file"
            multiple
            onChange={(e) => {
              const files = Array.from(e.target.files ?? []);
              if (files.length === 0) return;
              setAttachments((prev) => [...prev, ...files]);
              e.currentTarget.value = "";
            }}
          />
        )}

        {!isUnauthenticated && attachments.length > 0 && (
          <div role="list" className="rows" aria-label="Files">
            {attachments.map((file, index) => (
              <div role="listitem" key={`${file.name}-${index}`}>
                <div className="content">
                  <FileRowContent
                    name={FileUtils.getFileNameWithoutExtension(file.name)}
                    extension={FileUtils.getFileExtension(file.name).toUpperCase()}
                    externalLinkUrl={null}
                    isUploading={false}
                    details={<li>{FileUtils.getReadableFileSize(file.size)}</li>}
                  />
                </div>
                <div className="actions">
                  <Button
                    outline
                    color="danger"
                    aria-label="Remove"
                    onClick={() => setAttachments((prev) => prev.filter((_, i) => i !== index))}
                  >
                    <Icon name="trash2" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}

        {isUnauthenticated && (
          <div className="text-gray-500 text-sm">We typically respond within 24 hours during business days.</div>
        )}

        {/* reCAPTCHA container for unauthenticated users */}
        {isUnauthenticated && recaptcha.container}
      </form>
    </Modal>
  );
}

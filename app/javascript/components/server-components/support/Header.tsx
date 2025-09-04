import { HelperClientProvider } from "@helperai/react";
import React from "react";
import { createCast } from "ts-safe-cast";

import { register } from "$app/utils/serverComponentUtil";

import { Button } from "$app/components/Button";
import { UnreadTicketsBadge } from "$app/components/support/UnreadTicketsBadge";
import { NewTicketModal } from "$app/components/support/NewTicketModal";
import { useOriginalLocation } from "$app/components/useOriginalLocation";

import logo from "$assets/images/logo.svg";

export function SupportHeader({
  onOpenNewTicket,
  hasHelperSession = true,
  recaptchaSiteKey = null,
}: {
  onOpenNewTicket: () => void;
  hasHelperSession?: boolean;
  recaptchaSiteKey?: string | null | undefined;
}) {
  const { pathname } = new URL(useOriginalLocation());
  const isHelpArticle =
    pathname.startsWith(Routes.help_center_root_path()) && pathname !== Routes.help_center_root_path();

  const [isNewTicketOpen, setIsNewTicketOpen] = React.useState(false);

  return (
    <>
      <h1 className="hidden group-[.sidebar-nav]/body:block">Help</h1>
      <h1 className="group-[.sidebar-nav]/body:hidden">
        <a href={Routes.root_path()} className="flex items-center">
          <img src={logo} alt="Gumroad" className="h-8 w-auto dark:invert" />
        </a>
      </h1>
      <div className="actions">
        {isHelpArticle ? (
          <a href={Routes.help_center_root_path()} className="button" aria-label="Search" title="Search">
            <span className="icon icon-solid-search"></span>
          </a>
        ) : hasHelperSession ? (
          <Button color="accent" onClick={onOpenNewTicket}>
            New ticket
          </Button>
        ) : (
          <Button color="accent" onClick={() => setIsNewTicketOpen(true)}>
            Contact Support
          </Button>
        )}
      </div>
      {hasHelperSession ? (
        <div role="tablist" className="col-span-full">
          <a
            href={Routes.help_center_root_path()}
            role="tab"
            aria-selected={pathname.startsWith(Routes.help_center_root_path())}
            className="pb-2"
          >
            Articles
          </a>
          <a
            href={Routes.support_index_path()}
            role="tab"
            aria-selected={pathname.startsWith(Routes.support_index_path())}
            className="flex items-center gap-2 border-b-2 pb-2"
          >
            Support tickets
            <UnreadTicketsBadge />
          </a>
        </div>
      ) : null}

      <NewTicketModal
        open={isNewTicketOpen}
        onClose={() => setIsNewTicketOpen(false)}
        onCreated={() => {
          setIsNewTicketOpen(false);
          // The modal will handle redirecting to confirmation page
        }}
        isUnauthenticated={!hasHelperSession}
        recaptchaSiteKey={recaptchaSiteKey}
      />
    </>
  );
}

type WrapperProps = {
  host?: string | null;
  session?: {
    email?: string | null;
    emailHash?: string | null;
    timestamp?: number | null;
    customerMetadata?: {
      name?: string | null;
      value?: number | null;
      links?: Record<string, string> | null;
    } | null;
    currentToken?: string | null;
  } | null;
  new_ticket_url: string;
  recaptcha_site_key?: string | null;
};

const Wrapper = ({ host, session, new_ticket_url, recaptcha_site_key }: WrapperProps) =>
  host && session ? (
    <HelperClientProvider host={host} session={session}>
      <SupportHeader
        onOpenNewTicket={() => (window.location.href = new_ticket_url)}
        recaptchaSiteKey={recaptcha_site_key}
      />
    </HelperClientProvider>
  ) : (
    <SupportHeader
      onOpenNewTicket={() => (window.location.href = new_ticket_url)}
      hasHelperSession={false}
      recaptchaSiteKey={recaptcha_site_key}
    />
  );

export default register({ component: Wrapper, propParser: createCast() });

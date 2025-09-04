import * as React from "react";

type FeatureFlags = {
  require_email_typo_acknowledgment: boolean;
  public_support_tickets_enabled: boolean;
};

const FeatureFlagsContext = React.createContext<FeatureFlags>({
  require_email_typo_acknowledgment: false,
  public_support_tickets_enabled: false,
});

export const FeatureFlagsProvider = FeatureFlagsContext.Provider;

export function useFeatureFlags() {
  return React.useContext(FeatureFlagsContext);
}

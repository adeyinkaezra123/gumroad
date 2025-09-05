import { cast } from "ts-safe-cast";

import { request } from "$app/utils/request";

export type ProductPurchase = {
  email: string;
  created: string;
  id: number;
  amount: number;
  displayed_price: string;
  formatted_gumroad_tax_amount: string;
  is_preorder_authorization: boolean;
  stripe_refunded: boolean | null;
  is_chargedback: boolean;
  is_chargeback_reversed: boolean;
  refunded_by: { id: number; email: string }[];
  error_code: string | null;
  purchase_state: string;
  gumroad_responsible_for_tax: boolean;
};

export type ProductPurchasesResult = {
  purchases: ProductPurchase[];
  page: number | null;
};

export async function fetchProductPurchases(
  productId: number,
  page: number,
  perPage: number,
  isAffiliateUser: boolean,
  userId: number | null,
) {
  const response = await request({
    method: "GET",
    url: Routes.purchases_admin_product_path(productId, {
      format: "json",
      page,
      per_page: perPage,
      is_affiliate_user: isAffiliateUser,
      user_id: userId,
    }),
    accept: "json",
  });
  if (!response.ok) throw new Error(`Server error ${response.status}`);

  return cast<ProductPurchasesResult>(await response.json());
}

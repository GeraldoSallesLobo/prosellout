import { redirect } from "next/navigation";
import { HOME_ROUTE } from "@/lib/routes";

export default function IndexPage() {
  redirect(HOME_ROUTE);
}

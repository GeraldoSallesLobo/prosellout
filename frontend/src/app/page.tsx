import { redirect } from "next/navigation";

const HOME_ROUTE = "/relatorio/status/mtd";

export default function IndexPage() {
  redirect(HOME_ROUTE);
}

import { redirect } from "next/navigation";

// The member's home is the dashboard at /.
export default function Home() {
  redirect("/");
}

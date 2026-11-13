import { redirect } from "next/navigation";

// A member's own profile dashboard is their home page.
export default function Profile() {
  redirect("/");
}

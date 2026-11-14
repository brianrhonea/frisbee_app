import type { Metadata } from "next";
import { JoinLink } from "@/components/JoinLink";
import { OpenInApp } from "@/components/OpenInApp";

export const metadata: Metadata = {
  title: { absolute: "You're invited to join a team on Stall 10" },
  description: "Open it in the Stall 10 app, or join on the web.",
  robots: { index: false },
};

type Props = { params: Promise<{ code: string }> };

export default async function Page({ params }: Props) {
  const code = (await params).code;
  return (
    <>
      <div className="page">
        <JoinLink code={code} />
      </div>
      <OpenInApp kind="join" id={code} />
    </>
  );
}

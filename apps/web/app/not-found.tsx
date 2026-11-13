import { GetTheApp } from "@/components/GetTheApp";

export default function NotFound() {
  return (
    <GetTheApp title="We couldn't find that">
      <p className="lead">It may have been removed, or it&apos;s only in the Stall 10 app.</p>
    </GetTheApp>
  );
}

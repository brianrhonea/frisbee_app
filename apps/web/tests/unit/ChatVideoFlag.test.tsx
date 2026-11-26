import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

// meta/flags as useLiveDoc would hand it: a document, null (missing), or undefined (loading / unreadable).
let flagsDoc: { data: unknown; error: string | null } = { data: undefined, error: null };
const callApi = vi.fn();

vi.mock("@/lib/live", () => ({ useLiveDoc: () => flagsDoc }));
vi.mock("@/lib/client", async () => ({
  ...(await vi.importActual<object>("@/lib/client")),
  callApi: (...a: unknown[]) => callApi(...a),
}));
vi.mock("@/lib/outbox", () => ({ submitOutbox: vi.fn(), queuedNotice: () => "" }));
vi.mock("@/lib/drafts", () => ({ loadDraft: () => "", saveDraft: vi.fn() }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user: { uid: "u1" } }) }));
vi.mock("@/components/Mentions", () => ({ MentionMenu: () => null, suggestionsAt: () => null }));

import { ChatComposer } from "@/components/ChatComposer";
import { ApiError } from "@/lib/client";

const renderComposer = (withMenu: boolean) =>
  render(
    <ChatComposer
      path="/v1/x"
      outbox={{ kind: "directMessage", target: "t" }}
      upload={{ targetId: "t" }}
      placeholder="Message"
      onCreatePoll={withMenu ? () => undefined : undefined}
    />,
  );

const fileInput = (c: HTMLElement) => c.querySelector('input[type="file"]') as HTMLInputElement;
const pick = (c: HTMLElement, ...files: File[]) => fireEvent.change(fileInput(c), { target: { files } });
const video = new File(["x"], "clip.mp4", { type: "video/mp4" });
const mov = new File(["x"], "clip.MOV", { type: "" });
const photo = new File(["x"], "pic.jpg", { type: "image/jpeg" });
const doc = new File(["x"], "plan.pdf", { type: "application/pdf" });

beforeEach(() => {
  flagsDoc = { data: undefined, error: null };
  callApi.mockReset();
  callApi.mockImplementation(() => new Promise(() => undefined)); // an upload that never finishes
});

describe.each([
  ["unreadable (loading)", { data: undefined, error: null }],
  ["unreadable (error)", { data: undefined, error: "Couldn't load this." }],
  ["missing document", { data: null, error: null }],
  ["videoUploads false", { data: { videoUploads: false }, error: null }],
  ["videoUploads mistyped", { data: { videoUploads: "true" }, error: null }],
])("video closed: %s", (_name, doc_) => {
  beforeEach(() => {
    flagsDoc = doc_ as typeof flagsDoc;
  });

  it("refuses a video (by type or by name) without calling the API", () => {
    const { container } = renderComposer(false);
    pick(container, video);
    expect(screen.getByRole("alert")).toHaveTextContent("Video uploads aren't available right now.");
    pick(container, mov);
    expect(callApi).not.toHaveBeenCalled();
    expect(screen.queryByText(/clip\./)).toBeNull();
  });

  it("still takes photos and documents", () => {
    const { container } = renderComposer(false);
    pick(container, photo, doc);
    expect(screen.getByText(/pic\.jpg/)).toBeInTheDocument();
    expect(screen.getByText(/plan\.pdf/)).toBeInTheDocument();
    expect(callApi).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("does not offer video in the attach button or menu", () => {
    renderComposer(false);
    expect(screen.getByRole("button", { name: "Attach files" })).toHaveAttribute("title", "Attach photos or files");
  });

  it("names photos and files, not video, in the attach menu", () => {
    renderComposer(true);
    fireEvent.click(screen.getByRole("button", { name: "Attach" }));
    expect(screen.getByRole("menuitem", { name: "Photo or file" })).toBeInTheDocument();
    expect(screen.queryByText(/video/i)).toBeNull();
  });
});

describe("video open: videoUploads true", () => {
  beforeEach(() => {
    flagsDoc = { data: { videoUploads: true }, error: null };
  });

  it("takes a video, and photos and documents", () => {
    const { container } = renderComposer(false);
    pick(container, video, photo, doc);
    expect(screen.queryByRole("alert")).toBeNull();
    expect(callApi).toHaveBeenCalledTimes(3);
    expect(callApi.mock.calls[0][2].body.contentType).toBe("video/mp4");
  });

  it("offers video in the attach button and menu", () => {
    const { unmount } = renderComposer(false);
    expect(screen.getByRole("button", { name: "Attach files" })).toHaveAttribute("title", "Attach photos, videos or files");
    unmount();
    renderComposer(true);
    fireEvent.click(screen.getByRole("button", { name: "Attach" }));
    expect(screen.getByRole("menuitem", { name: "Photo, video or file" })).toBeInTheDocument();
  });

  it("shows the API's 412 when the flag was turned off after the page loaded", async () => {
    callApi.mockRejectedValue(new ApiError("Video uploads aren't available right now.", 412, "failed_precondition"));
    const { container } = renderComposer(false);
    pick(container, video);
    await waitFor(() => expect(screen.getByText(/Video uploads aren't available right now\./)).toBeInTheDocument());
    expect(screen.getByText(/clip\.mp4/)).toHaveTextContent("clip.mp4");
  });
});

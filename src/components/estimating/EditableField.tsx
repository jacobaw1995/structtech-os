"use client";

import { useRef, useState, useTransition } from "react";

// The one tap-to-edit-in-place primitive for the whole document (Chunk 3 of
// the estimate builder rebuild) — every editable field on the page is an
// instance of this, not a bespoke per-field editor. Mirrors the
// display/edit toggle + onBlur -> startTransition(formRef.requestSubmit())
// mechanics of ChecklistFieldRow (Lead Control Center), but the VISUAL
// treatment is deliberately different: no boxed border, no status icon, no
// "Tap to enter" callout. The document must still look like a document
// while editing (Jacob, Chunk 3) — display mode is plain text with a
// Notion-style hover highlight as the only affordance; edit mode keeps the
// exact same typography and swaps only a thin bottom border in for the
// highlight, so nothing about the page's proportions jumps.
//
// Parent components should key each instance on its current value (e.g.
// `key={`contact_name-${estimate.contact_name}`}`) — same reason
// ChecklistCard keys its rows on `${field.key}-${filled}`: a server action
// redirect() revalidates and re-renders with the new value, and remounting
// via the key reset is what returns this component to display mode without
// any extra "onSaved" plumbing.

type FieldType = "text" | "number" | "date" | "tel" | "email" | "textarea";

export function EditableField({
  value,
  display,
  placeholder,
  action,
  hidden,
  name,
  type = "text",
  locked = false,
  className = "",
  align,
  block = false,
}: {
  value: string;
  display?: string;
  placeholder?: string;
  action: (formData: FormData) => void;
  hidden: Record<string, string>;
  name: string;
  type?: FieldType;
  locked?: boolean;
  className?: string;
  align?: "left" | "right";
  block?: boolean;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  const alignClass = align === "right" ? "text-right" : "text-left";
  const shown = display ?? value;

  if (locked) {
    return (
      <span className={`${className} ${alignClass} ${block ? "block whitespace-pre-wrap" : ""}`}>
        {shown || "—"}
      </span>
    );
  }

  if (!isEditing) {
    return (
      <button
        type="button"
        onClick={() => setIsEditing(true)}
        className={`${className} ${alignClass} ${
          block ? "block w-full whitespace-pre-wrap" : "inline-block"
        } -mx-1 rounded px-1 outline-none transition-colors hover:bg-accent-soft/60 focus:bg-accent-soft/60`}
      >
        {shown || <span className="italic text-muted">{placeholder || "—"}</span>}
      </button>
    );
  }

  const inputClass = `${className} ${alignClass} w-full border-b border-accent bg-transparent outline-none disabled:opacity-60`;

  return (
    <form ref={formRef} action={action} className={block ? "block w-full" : "inline-block"}>
      {Object.entries(hidden).map(([key, val]) => (
        <input key={key} type="hidden" name={key} value={val} />
      ))}
      {type === "textarea" ? (
        <textarea
          name={name}
          autoFocus
          disabled={isPending}
          defaultValue={value}
          placeholder={placeholder}
          rows={3}
          onBlur={submit}
          className={`${inputClass} resize-none`}
        />
      ) : (
        <input
          name={name}
          type={type}
          inputMode={type === "number" ? "decimal" : undefined}
          step={type === "number" ? "any" : undefined}
          autoFocus
          disabled={isPending}
          defaultValue={value}
          placeholder={placeholder}
          onBlur={submit}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              submit();
            }
          }}
          className={inputClass}
        />
      )}
    </form>
  );
}

"use client";

import { useRef, useTransition } from "react";

// Small client island (same pattern as crm/StageSelect) — auto-submits on
// change so the phase/status cells behave like dropdowns, not
// select-then-hunt-for-a-save-button forms. Generic over which action it
// posts to since phase and status are otherwise identical shapes.
export function InlineFieldSelect({
  action,
  orgId,
  itemId,
  fieldName,
  value,
  options,
  className,
}: {
  action: (formData: FormData) => void;
  orgId: string;
  itemId: string;
  fieldName: string;
  value: string;
  options: readonly { key: string; label: string }[];
  className?: string;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <form ref={formRef} action={action}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="itemId" value={itemId} />
      <select
        name={fieldName}
        defaultValue={value}
        disabled={isPending}
        onChange={() =>
          startTransition(() => {
            formRef.current?.requestSubmit();
          })
        }
        className={
          className ??
          "rounded-md border border-border bg-bg px-2 py-1 text-xs text-text outline-none focus:border-accent disabled:opacity-60"
        }
      >
        {options.map((o) => (
          <option key={o.key} value={o.key}>
            {o.label}
          </option>
        ))}
      </select>
    </form>
  );
}

"use client";

import { useRef, useState, useTransition } from "react";
import {
  updateDealColumnField,
  updateDealServiceAddress,
  updateChecklistField,
} from "@/lib/crm/actions";
import type { FieldConfig, LeadTypeOption } from "@/lib/crm/command-center";

// The core "form == checklist" row (LEAD_CONTROL_CENTER_SPEC.md): empty ->
// hollow circle + emptyHint, tap anywhere to type inline; filled -> value +
// green check + pencil to re-edit. One component handles every field type
// in config — nothing here is specific to a particular field key, only to
// FieldConfig.type/source.kind, so a tenant's config can add/reorder
// fields without a code change.
//
// Write path is picked from field.source.kind: "json" -> updateChecklistField
// (deals.intake_checklist), "column" -> updateDealColumnField (generic,
// field-key-switched on the server), "columns" -> updateDealServiceAddress
// (the one composite field today — see command-center.ts's FieldSourceConfig
// comment). "computed"/"external"/readonly render with no edit affordance.
export function ChecklistFieldRow({
  orgId,
  dealId,
  stage,
  field,
  value,
  filled,
  columnValues,
  leadTypeOptions,
  remodelOptions,
}: {
  orgId: string;
  dealId: string;
  stage: string;
  field: FieldConfig;
  value: unknown;
  filled: boolean;
  columnValues?: Record<string, string>;
  leadTypeOptions: LeadTypeOption[];
  remodelOptions: LeadTypeOption[];
}) {
  const editable = field.type !== "readonly" && field.source.kind !== "computed" && field.source.kind !== "external";
  const [isEditing, setIsEditing] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  const displayValue = formatDisplayValue(value);

  if (!editable) {
    return (
      <div className="flex items-center justify-between gap-3 border-b border-border py-3 last:border-b-0">
        <div className="flex flex-col gap-0.5">
          <span className="text-xs font-medium uppercase tracking-wide text-muted">{field.label}</span>
          <span className="text-sm text-text">{displayValue || "—"}</span>
        </div>
      </div>
    );
  }

  if (!isEditing) {
    return (
      <button
        type="button"
        onClick={() => setIsEditing(true)}
        className="flex min-h-14 w-full items-center justify-between gap-3 border-b border-border py-3 text-left last:border-b-0 sm:min-h-0"
      >
        <div className="flex flex-col gap-0.5">
          <span className="text-xs font-medium uppercase tracking-wide text-muted">{field.label}</span>
          {filled ? (
            <span className="text-sm text-text">{displayValue}</span>
          ) : (
            <span className="text-sm text-muted">{field.emptyHint || "Tap to enter"}</span>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {filled && <PencilIcon />}
          <StatusIcon filled={filled} />
        </div>
      </button>
    );
  }

  if (field.type === "address" && field.source.kind === "columns") {
    // Form-level blur, not per-input: tabbing from Street to City fires a
    // blur on Street too, and a per-input onBlur={submit} would fire that
    // premature submit before the other three fields are filled in. Only
    // submit once focus leaves the form entirely.
    const submitIfLeavingForm = (e: React.FocusEvent<HTMLFormElement>) => {
      if (!e.currentTarget.contains(e.relatedTarget as Node | null)) {
        submit();
      }
    };
    return (
      <form
        ref={formRef}
        action={updateDealServiceAddress}
        onBlur={submitIfLeavingForm}
        className="flex flex-col gap-2 border-b border-border py-3 last:border-b-0"
      >
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="dealId" value={dealId} />
        <input type="hidden" name="stage" value={stage} />
        <span className="text-xs font-medium uppercase tracking-wide text-muted">{field.label}</span>
        <input
          name="street"
          placeholder="Street"
          autoFocus
          disabled={isPending}
          defaultValue={columnValues?.[field.source.columns[0]] ?? ""}
          className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm"
        />
        <div className="grid grid-cols-3 gap-2">
          <input
            name="city"
            placeholder="City"
            disabled={isPending}
            defaultValue={columnValues?.[field.source.columns[1]] ?? ""}
            className="min-h-14 rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm"
          />
          <input
            name="state"
            placeholder="State"
            disabled={isPending}
            defaultValue={columnValues?.[field.source.columns[2]] ?? ""}
            className="min-h-14 rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm"
          />
          <input
            name="zip"
            placeholder="ZIP"
            disabled={isPending}
            defaultValue={columnValues?.[field.source.columns[3]] ?? ""}
            className="min-h-14 rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm"
          />
        </div>
      </form>
    );
  }

  // JSON-sourced (deals.intake_checklist) vs column-sourced — same input
  // widgets below, different form/action wrapping.
  const isJson = field.source.kind === "json";
  const inputWidget = (
    <FieldInput
      field={field}
      defaultValue={displayValue}
      disabled={isPending}
      onBlur={submit}
      onEnter={submit}
      leadTypeOptions={leadTypeOptions}
      remodelOptions={remodelOptions}
    />
  );

  return (
    <form
      ref={formRef}
      action={isJson ? updateChecklistField : updateDealColumnField}
      className="flex flex-col gap-1 border-b border-border py-3 last:border-b-0"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="dealId" value={dealId} />
      <input type="hidden" name="stage" value={stage} />
      {isJson && field.source.kind === "json" && (
        <>
          <input type="hidden" name="path" value={JSON.stringify(field.source.path)} />
          <input type="hidden" name="field_type" value={field.type} />
        </>
      )}
      {!isJson && <input type="hidden" name="field" value={field.key} />}
      <span className="text-xs font-medium uppercase tracking-wide text-muted">{field.label}</span>
      {inputWidget}
    </form>
  );
}

function FieldInput({
  field,
  defaultValue,
  disabled,
  onBlur,
  onEnter,
  leadTypeOptions,
  remodelOptions,
}: {
  field: FieldConfig;
  defaultValue: string;
  disabled: boolean;
  onBlur: () => void;
  onEnter: () => void;
  leadTypeOptions: LeadTypeOption[];
  remodelOptions: LeadTypeOption[];
}) {
  const baseClass =
    "min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm";

  if (field.type === "select" && field.key === "lead_type") {
    return (
      <select name="value" autoFocus disabled={disabled} defaultValue={defaultValue} onChange={onBlur} className={baseClass}>
        <option value="">—</option>
        {leadTypeOptions.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    );
  }
  if (field.type === "select" && field.key === "remodel_or_new_construction") {
    return (
      <select name="value" autoFocus disabled={disabled} defaultValue={defaultValue} onChange={onBlur} className={baseClass}>
        <option value="">—</option>
        {remodelOptions.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    );
  }
  if (field.type === "textarea") {
    return (
      <textarea
        name="value"
        autoFocus
        rows={3}
        disabled={disabled}
        defaultValue={defaultValue}
        onBlur={onBlur}
        placeholder={field.emptyHint}
        className={baseClass}
      />
    );
  }

  const inputType =
    field.type === "number" ? "number" : field.type === "date" ? "date" : field.type === "email" ? "email" : field.type === "phone" ? "tel" : "text";

  return (
    <input
      name="value"
      type={inputType}
      step={field.type === "number" ? "any" : undefined}
      autoFocus
      disabled={disabled}
      defaultValue={defaultValue}
      placeholder={field.type === "roof_types" ? "Comma-separated" : field.emptyHint}
      onBlur={onBlur}
      onKeyDown={(e) => {
        if (e.key === "Enter" && field.type !== "textarea") {
          e.preventDefault();
          onEnter();
        }
      }}
      className={baseClass}
    />
  );
}

function formatDisplayValue(value: unknown): string {
  if (value == null) return "";
  if (Array.isArray(value)) return value.join(", ");
  return String(value);
}

function PencilIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-4 w-4 shrink-0 text-muted">
      <path
        d="M13.5 3.5l3 3-9 9H4.5v-3l9-9z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function StatusIcon({ filled }: { filled: boolean }) {
  if (filled) {
    return (
      <svg viewBox="0 0 20 20" fill="none" className="h-6 w-6 shrink-0 text-accent-strong">
        <circle cx="10" cy="10" r="9" fill="currentColor" />
        <path d="M6 10.5l2.5 2.5L14 7.5" stroke="white" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-6 w-6 shrink-0 text-border">
      <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.75" />
    </svg>
  );
}

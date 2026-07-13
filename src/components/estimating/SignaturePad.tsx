"use client";

import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
import { useOutdoorMode } from "@/lib/estimating/outdoor-context";

export type SignaturePadHandle = {
  clear: () => void;
  isEmpty: () => boolean;
  toDataUrl: () => string | null;
};

// Uncontrolled canvas — StepSign reads its content only at submit time via
// the imperative handle, same reason server actions elsewhere read a
// hidden-input ref rather than mirroring every keystroke into React state.
export const SignaturePad = forwardRef<
  SignaturePadHandle,
  { onDirtyChange?: (dirty: boolean) => void }
>(function SignaturePad({ onDirtyChange }, ref) {
  const outdoor = useOutdoorMode();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const drawingRef = useRef(false);
  const dirtyRef = useRef(false);
  const [, forceRender] = useState(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ratio = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * ratio;
    canvas.height = rect.height * ratio;
    const ctx = canvas.getContext("2d");
    if (ctx) {
      ctx.scale(ratio, ratio);
      ctx.lineWidth = 2.5;
      ctx.lineCap = "round";
      ctx.strokeStyle = outdoor ? "#ffffff" : "#1a1a1a";
    }
  }, [outdoor]);

  useImperativeHandle(ref, () => ({
    clear() {
      const canvas = canvasRef.current;
      const ctx = canvas?.getContext("2d");
      if (canvas && ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
      dirtyRef.current = false;
      onDirtyChange?.(false);
      forceRender((n) => n + 1);
    },
    isEmpty() {
      return !dirtyRef.current;
    },
    toDataUrl() {
      if (!dirtyRef.current) return null;
      return canvasRef.current?.toDataURL("image/png") ?? null;
    },
  }));

  function pointFromEvent(e: React.PointerEvent<HTMLCanvasElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  }

  function handlePointerDown(e: React.PointerEvent<HTMLCanvasElement>) {
    const ctx = canvasRef.current?.getContext("2d");
    if (!ctx) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    drawingRef.current = true;
    const { x, y } = pointFromEvent(e);
    ctx.beginPath();
    ctx.moveTo(x, y);
  }

  function handlePointerMove(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!drawingRef.current) return;
    const ctx = canvasRef.current?.getContext("2d");
    if (!ctx) return;
    const { x, y } = pointFromEvent(e);
    ctx.lineTo(x, y);
    ctx.stroke();
    if (!dirtyRef.current) {
      dirtyRef.current = true;
      onDirtyChange?.(true);
    }
  }

  function handlePointerUp() {
    drawingRef.current = false;
  }

  return (
    <canvas
      ref={canvasRef}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerLeave={handlePointerUp}
      className={`h-44 w-full touch-none rounded-lg border-2 ${
        outdoor ? "border-white bg-black" : "border-border bg-bg"
      }`}
    />
  );
});

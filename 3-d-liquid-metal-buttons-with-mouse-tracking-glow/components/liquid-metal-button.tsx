"use client"

import type React from "react"
import type { LucideIcon } from "lucide-react"

import { useState, useRef } from "react"

interface LiquidMetalButtonProps {
  icon: LucideIcon
  animationType?:
    | "slide-right" // Arrow
    | "bounce" // Home
    | "zoom" // Search
    | "spin" // Settings
    | "wave" // User
    | "shake" // Bell
    | "heartbeat" // Heart
    | "spread" // Share
    | "drop" // Download
    | "pulse" // Play
    | "rotate-in" // Plus
    | "flip" // Mail
    | "flash" // Camera
    | "bounce-beat" // Music
    | "record" // Video
    | "slide-down" // Bookmark
    | "lock-shake" // Lock
    | "signal" // Wifi
    | "phase" // Moon
    | "spark" // Zap
    | "rotate" // Globe
    | "float" // Cloud
    | "pulse-ring" // Mic
    | "fly" // Send
  size?: "sm" | "md" | "lg"
}

const getClickAnimation = (type: string): React.CSSProperties => {
  const animations: Record<string, React.CSSProperties> = {
    "slide-right": { transform: "translateX(8px) scale(1.2)", color: "#ffffff" },
    bounce: { transform: "translateY(-10px) scale(1.2)", color: "#ffffff" },
    zoom: { transform: "scale(1.5)", color: "#ffffff" },
    spin: { transform: "rotate(180deg) scale(1.1)", color: "#ffffff" },
    wave: { transform: "rotate(-15deg) scale(1.2)", color: "#ffffff" },
    shake: { transform: "rotate(20deg) scale(1.2)", color: "#ffffff" },
    heartbeat: { transform: "scale(1.4)", color: "#ff6b6b" },
    spread: { transform: "scale(1.3) rotate(15deg)", color: "#ffffff" },
    drop: { transform: "translateY(6px) scale(1.2)", color: "#ffffff" },
    pulse: { transform: "scale(1.4)", color: "#ffffff" },
    "rotate-in": { transform: "rotate(90deg) scale(1.3)", color: "#ffffff" },
    flip: { transform: "rotateY(180deg) scale(1.2)", color: "#ffffff" },
    flash: { transform: "scale(1.5)", color: "#ffff00" },
    "bounce-beat": { transform: "translateY(-6px) scale(1.2)", color: "#ffffff" },
    record: { transform: "scale(1.3)", color: "#ff4444" },
    "slide-down": { transform: "translateY(4px) scale(1.2)", color: "#ffffff" },
    "lock-shake": { transform: "translateX(4px) scale(1.2)", color: "#ffffff" },
    signal: { transform: "scale(1.3)", color: "#4ade80" },
    phase: { transform: "rotate(-30deg) scale(1.2)", color: "#fbbf24" },
    spark: { transform: "scale(1.4) rotate(15deg)", color: "#facc15" },
    rotate: { transform: "rotate(360deg) scale(1.1)", color: "#60a5fa" },
    float: { transform: "translateY(-8px) scale(1.2)", color: "#ffffff" },
    "pulse-ring": { transform: "scale(1.3)", color: "#ef4444" },
    fly: { transform: "translate(10px, -10px) scale(1.2)", color: "#ffffff" },
  }
  return animations[type] || { transform: "scale(1.3) rotate(15deg)", color: "#ffffff" }
}

const getGlowColor = (type: string): string => {
  const glows: Record<string, string> = {
    heartbeat: "rgba(255, 107, 107, 0.9)",
    flash: "rgba(255, 255, 0, 0.9)",
    record: "rgba(255, 68, 68, 0.9)",
    signal: "rgba(74, 222, 128, 0.9)",
    phase: "rgba(251, 191, 36, 0.9)",
    spark: "rgba(250, 204, 21, 0.9)",
    rotate: "rgba(96, 165, 250, 0.9)",
    "pulse-ring": "rgba(239, 68, 68, 0.9)",
  }
  return glows[type] || "rgba(255, 255, 255, 0.9)"
}

export function LiquidMetalButton({ icon: Icon, animationType = "slide-right", size = "md" }: LiquidMetalButtonProps) {
  const [mousePosition, setMousePosition] = useState({ x: 0, y: 0 })
  const [isHovering, setIsHovering] = useState(false)
  const [isPressed, setIsPressed] = useState(false)
  const [isClicked, setIsClicked] = useState(false)
  const [shakePhase, setShakePhase] = useState(0)
  const buttonRef = useRef<HTMLButtonElement>(null)

  const sizeConfig = {
    sm: { padding: "px-5 py-3", icon: "h-4 w-4", glow: "60px", ambient: "-inset-4" },
    md: { padding: "px-8 py-5", icon: "h-6 w-6", glow: "80px", ambient: "-inset-8" },
    lg: { padding: "px-10 py-6", icon: "h-8 w-8", glow: "100px", ambient: "-inset-10" },
  }

  const config = sizeConfig[size]

  const handleMouseMove = (e: React.MouseEvent<HTMLButtonElement>) => {
    if (!buttonRef.current) return

    const rect = buttonRef.current.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    setMousePosition({ x, y })
  }

  const handleClick = () => {
    setIsClicked(true)

    if (animationType === "shake" || animationType === "lock-shake") {
      let count = 0
      const shakeInterval = setInterval(() => {
        setShakePhase((prev) => (prev === 1 ? -1 : 1))
        count++
        if (count >= 6) {
          clearInterval(shakeInterval)
          setShakePhase(0)
        }
      }, 50)
    }

    setTimeout(() => setIsClicked(false), 500)
  }

  const clickAnimationStyle = getClickAnimation(animationType)
  const glowColor = getGlowColor(animationType)

  const getIconTransform = () => {
    if (isClicked) {
      if ((animationType === "shake" || animationType === "lock-shake") && shakePhase !== 0) {
        return `translateX(${shakePhase * 4}px) scale(1.2)`
      }
      return clickAnimationStyle.transform
    }
    if (isPressed) return "scale(0.95)"
    if (isHovering) return "scale(1.05)"
    return "scale(1)"
  }

  const getIconColor = () => {
    if (isClicked) return clickAnimationStyle.color
    if (isPressed) return "#9ca3af"
    if (isHovering) return "#9ca3af"
    return "#6b7280"
  }

  return (
    <button
      ref={buttonRef}
      onMouseMove={handleMouseMove}
      onMouseEnter={() => setIsHovering(true)}
      onMouseLeave={() => {
        setIsHovering(false)
        setIsPressed(false)
      }}
      onMouseDown={() => setIsPressed(true)}
      onMouseUp={() => setIsPressed(false)}
      onClick={handleClick}
      className="group relative inline-flex items-center justify-center touch-manipulation"
      style={{
        transform: isPressed ? "translateY(4px)" : "translateY(0)",
        transition: "transform 0.1s ease-out",
      }}
    >
      <div
        className={`pointer-events-none absolute ${config.ambient} rounded-full blur-3xl transition-opacity duration-500`}
        style={{
          background: `radial-gradient(200px circle at ${mousePosition.x + 32}px ${mousePosition.y + 32}px, rgba(255, 255, 255, 0.15), transparent 60%)`,
          opacity: isHovering ? (isPressed ? 0.5 : 1) : 0,
        }}
      />

      <div
        className="relative rounded-full bg-gradient-to-b from-[#1a1a1a] to-[#0a0a0a] p-[3px] transition-all duration-100"
        style={{
          boxShadow: isPressed
            ? "0 5px 15px rgba(0,0,0,0.8), 0 2px 5px rgba(0,0,0,0.6)"
            : "0 25px 50px rgba(0,0,0,0.8), 0 10px 20px rgba(0,0,0,0.6)",
        }}
      >
        <div className="relative overflow-hidden rounded-full p-[2px]">
          <div className="absolute inset-0 rounded-full bg-gradient-to-b from-[#4a4a4a] via-[#2a2a2a] to-[#3a3a3a]" />

          <div
            className="absolute inset-0 rounded-full transition-opacity duration-150"
            style={{
              background: isHovering
                ? `radial-gradient(${config.glow} circle at ${mousePosition.x}px ${mousePosition.y}px, 
                    rgba(255, 255, 255, 0.95) 0%, 
                    rgba(255, 255, 255, 0.6) 25%, 
                    rgba(220, 230, 255, 0.3) 50%, 
                    transparent 70%)`
                : "transparent",
              opacity: isPressed ? 1.2 : 1,
            }}
          />

          <div className="relative overflow-hidden rounded-full">
            <div
              className="absolute inset-0 rounded-full transition-opacity duration-150"
              style={{
                background: isHovering
                  ? `radial-gradient(60px circle at ${mousePosition.x}px ${mousePosition.y}px, 
                      rgba(255, 255, 255, 0.06) 0%, 
                      transparent 60%)`
                  : "transparent",
              }}
            />

            <div
              className="absolute inset-0 rounded-full bg-white/5 transition-all"
              style={{
                background: `radial-gradient(circle, ${glowColor.replace("0.9", "0.3")} 0%, transparent 70%)`,
                transform: isClicked ? "scale(2)" : "scale(0)",
                opacity: isClicked ? 0 : 1,
                transition: "transform 0.5s ease-out, opacity 0.5s ease-out",
              }}
            />

            <div
              className={`relative rounded-full bg-gradient-to-b from-[#252525] to-[#181818] ${config.padding} transition-all duration-100`}
              style={{
                boxShadow: isPressed
                  ? "inset 0 8px 20px rgba(0,0,0,0.8), inset 0 2px 8px rgba(0,0,0,0.6)"
                  : "inset 0 4px 12px rgba(0,0,0,0.6), inset 0 -1px 4px rgba(255,255,255,0.03)",
              }}
            >
              <div
                className="absolute inset-x-0 top-0 h-1/3 rounded-t-full bg-gradient-to-b from-white/8 via-white/2 to-transparent transition-opacity duration-100"
                style={{ opacity: isPressed ? 0.3 : 1 }}
              />

              <div className="absolute inset-x-0 bottom-0 h-1/4 rounded-b-full bg-gradient-to-t from-black/30 to-transparent" />

              <Icon
                className={`relative z-10 ${config.icon}`}
                strokeWidth={1.5}
                style={{
                  color: getIconColor(),
                  transform: getIconTransform(),
                  filter: isClicked
                    ? `drop-shadow(0 0 15px ${glowColor})`
                    : isPressed
                      ? "drop-shadow(0 0 10px rgba(255, 255, 255, 0.5))"
                      : isHovering
                        ? "drop-shadow(0 0 6px rgba(255, 255, 255, 0.3))"
                        : "none",
                  transition:
                    animationType === "spin" || animationType === "rotate"
                      ? "transform 0.5s cubic-bezier(0.34, 1.56, 0.64, 1), color 0.15s ease-out, filter 0.15s ease-out"
                      : "transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1), color 0.15s ease-out, filter 0.15s ease-out",
                }}
              />

              <div className="absolute inset-0 rounded-full border border-gray-600/20" />

              <div
                className="absolute inset-0 rounded-full bg-white/5 transition-opacity duration-100"
                style={{ opacity: isPressed ? 1 : 0 }}
              />
            </div>
          </div>
        </div>

        <div
          className="absolute inset-x-6 top-1 h-[1px] rounded-full bg-gradient-to-r from-transparent via-white/20 to-transparent transition-opacity duration-100"
          style={{ opacity: isPressed ? 0 : 1 }}
        />
      </div>
    </button>
  )
}

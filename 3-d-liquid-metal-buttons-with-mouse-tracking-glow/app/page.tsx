import { LiquidMetalButton } from "@/components/liquid-metal-button"
import {
  ArrowRight,
  Home,
  Search,
  Settings,
  User,
  Bell,
  Heart,
  Share2,
  Download,
  Play,
  Plus,
  Mail,
  Camera,
  Music,
  Video,
  Bookmark,
  Lock,
  Wifi,
  Moon,
  Zap,
  Globe,
  Cloud,
  Mic,
  Send,
} from "lucide-react"

export default function Page() {
  const icons = [
    { icon: ArrowRight, label: "Next", animation: "slide-right" },
    { icon: Home, label: "Home", animation: "bounce" },
    { icon: Search, label: "Search", animation: "zoom" },
    { icon: Settings, label: "Settings", animation: "spin" },
    { icon: User, label: "Profile", animation: "wave" },
    { icon: Bell, label: "Notifications", animation: "shake" },
    { icon: Heart, label: "Favorites", animation: "heartbeat" },
    { icon: Share2, label: "Share", animation: "spread" },
    { icon: Download, label: "Download", animation: "drop" },
    { icon: Play, label: "Play", animation: "pulse" },
    { icon: Plus, label: "Add", animation: "rotate-in" },
    { icon: Mail, label: "Mail", animation: "flip" },
    { icon: Camera, label: "Camera", animation: "flash" },
    { icon: Music, label: "Music", animation: "bounce-beat" },
    { icon: Video, label: "Video", animation: "record" },
    { icon: Bookmark, label: "Bookmark", animation: "slide-down" },
    { icon: Lock, label: "Lock", animation: "lock-shake" },
    { icon: Wifi, label: "Wifi", animation: "signal" },
    { icon: Moon, label: "Dark Mode", animation: "phase" },
    { icon: Zap, label: "Flash", animation: "spark" },
    { icon: Globe, label: "Web", animation: "rotate" },
    { icon: Cloud, label: "Cloud", animation: "float" },
    { icon: Mic, label: "Voice", animation: "pulse-ring" },
    { icon: Send, label: "Send", animation: "fly" },
  ] as const

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-8 bg-black px-4 py-12 sm:gap-12 sm:py-20">
      <div className="grid w-full max-w-5xl grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 md:gap-8 lg:grid-cols-6">
        {icons.map(({ icon, label, animation }) => (
          <div key={label} className="flex flex-col items-center gap-2 sm:gap-4">
            <div className="block sm:hidden">
              <LiquidMetalButton icon={icon} animationType={animation} size="sm" />
            </div>
            <div className="hidden sm:block">
              <LiquidMetalButton icon={icon} animationType={animation} size="md" />
            </div>
            <span className="text-[10px] text-gray-500 sm:text-xs">{label}</span>
          </div>
        ))}
      </div>

      <footer className="mt-4 text-center text-xs text-gray-500 sm:mt-8 sm:text-sm">
        built using{" "}
        <a href="https://v0.dev" className="text-gray-400 transition-colors hover:text-white">
          v0
        </a>{" "}
        by{" "}
        <a href="https://jess.vc" className="text-gray-400 transition-colors hover:text-white">
          jessin
        </a>
      </footer>
    </div>
  )
}

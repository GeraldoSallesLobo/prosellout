import Image from "next/image";
import clsx from "clsx";

const LOGO_WIDTH = 702;
const LOGO_HEIGHT = 364;

interface BrandLogoProps {
  className?: string;
  priority?: boolean;
  size?: "login" | "sidebar";
}

const LOGO_SIZE_CLASSES: Record<NonNullable<BrandLogoProps["size"]>, string> = {
  login: "h-24 w-72",
  sidebar: "h-12 w-36",
};

const LOGO_IMAGE_SIZES: Record<NonNullable<BrandLogoProps["size"]>, string> = {
  login: "288px",
  sidebar: "144px",
};

export function BrandLogo({ className, priority = false, size = "sidebar" }: BrandLogoProps) {
  return (
    <span
      className={clsx(
        "inline-flex shrink-0 items-center justify-center overflow-hidden rounded-md bg-white p-1 ring-1 ring-black/5",
        LOGO_SIZE_CLASSES[size],
        className,
      )}
    >
      <Image
        src="/prosellout_logo.png"
        alt="ProSellOut"
        width={LOGO_WIDTH}
        height={LOGO_HEIGHT}
        priority={priority}
        sizes={LOGO_IMAGE_SIZES[size]}
        className="h-full w-full object-cover"
      />
    </span>
  );
}

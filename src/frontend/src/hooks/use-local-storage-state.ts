"use client";

import { useEffect, useState, type Dispatch, type SetStateAction } from "react";

/**
 * React state synced with localStorage.
 * Renders with the initial value first (SSR-safe), then hydrates from storage.
 */
export function useLocalStorageState<T>(
  key: string,
  initialValue: T,
): [T, Dispatch<SetStateAction<T>>] {
  const [value, setValue] = useState<T>(initialValue);
  const [isHydrated, setIsHydrated] = useState(false);

  useEffect(() => {
    const storedValue = window.localStorage.getItem(key);
    if (storedValue !== null) {
      try {
        setValue(JSON.parse(storedValue) as T);
      } catch {
        // Corrupted entry — keep the initial value.
      }
    }
    setIsHydrated(true);
  }, [key]);

  useEffect(() => {
    if (!isHydrated) return;
    window.localStorage.setItem(key, JSON.stringify(value));
  }, [key, value, isHydrated]);

  return [value, setValue];
}

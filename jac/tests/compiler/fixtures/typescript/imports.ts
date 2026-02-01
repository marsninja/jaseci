// Various import styles
import React from "react";
import { useState, useEffect } from "react";
import type { FC, ReactNode } from "react";
import * as utils from "./utils";

export { React, useState };

export interface AppProps {
  title: string;
  children?: ReactNode;
}

export const App: FC<AppProps> = ({ title, children }) => {
  const [count, setCount] = useState<number>(0);
  return null;
};

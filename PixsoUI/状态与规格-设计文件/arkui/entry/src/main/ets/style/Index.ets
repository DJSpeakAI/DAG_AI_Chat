import style from "./style.json"

type ColorStop = (string | number)[];

interface LinearGradientValue {
  angle: number;
  colors: ColorStop[];
}

interface LinearGradient {
  styleId: string;
  name: string;
  value: LinearGradientValue;
}


interface RadialGradientValue {
  center: string[];
  radius: string;
  colors: ColorStop[];
}

interface RadialGradient {
  styleId: string;
  name: string;
  value: RadialGradientValue;
}

interface SweepGradientValue {
  center: string[];
  start: number;
  end: number;
  rotation: number;
  colors: ColorStop[];
}

interface SweepGradient {
  styleId: string;
  name: string;
  value: SweepGradientValue;
}

interface DropShadowValue {
  color: string;
  radius: number;
  offsetX: number;
  offsetY: number;
  fill: boolean;
}

interface DropShadow {
  styleId: string;
  name: string;
  value: DropShadowValue;
}

export interface Text {
  fontFamily: string;
  fontSize: number;
  fontStyle: string;
  letterSpacing: number | string;
  lineHeight: string;
  name: string;
  styleId: string;
}

export function getStyleValue(
  type: string,
  id: string,
): LinearGradientOptions | RadialGradientOptions | SweepGradientOptions | ShadowOptions | Text | string {
  switch (type) {
    case "linearGradient": {
      const result: LinearGradient | undefined =
        (style.linearGradient as LinearGradient[]).find((item) => item.styleId === id);
      if (result) {
        return result.value as LinearGradientOptions;
      } else {
        return "";
      }
    }
    case "radialGradient": {
      const result: RadialGradient | undefined =
        (style.radialGradient as RadialGradient[]).find((item) => item.styleId === id);
      if (result) {
        return result.value as RadialGradientOptions;
      } else {
        return "";
      }
    }
    case "sweepGradient": {
      const result: SweepGradient | undefined =
        (style.sweepGradient as SweepGradient[]).find((item) => item.styleId === id);
      if (result) {
        return result.value as SweepGradientOptions;
      } else {
        return "";
      }
    }
    case "dropShadow": {
      const result: DropShadow | undefined =
        (style.dropShadow as DropShadow[]).find((item) => item.styleId === id);
      if (result) {
        return result.value as ShadowOptions;
      } else {
        return "";
      }
    }
    case "text": {
      const result: Text | undefined =
        (style.text as Text[]).find((item) => item.styleId === id);
      if (result) {
        return result
      } else {
        return "";
      }
    }
    default:
      return "";
  }
}

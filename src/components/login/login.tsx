import { useEffect, useState } from "react";
import {
  Alert,
  Anchor,
  Button,
  PasswordInput,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { useForm } from "@mantine/form";
import {
  IconAlertCircle,
  IconArrowLeft,
  IconCircleCheck,
  IconKey,
  IconLock,
  IconLogin2,
  IconMail,
  IconSend,
  IconTruck,
} from "@tabler/icons-react";
import classes from "./login.module.css";

// City grid (decorative backdrop).
const STREETS = [
  ...[120, 260, 400, 540, 680].map((y) => `M24 ${y} L602 ${y}`),
  ...[110, 250, 390, 530].map((x) => `M${x} 24 L${x} 716`),
].join(" ");

// Geofences are polygons (outline only). "hot" is the zone a vehicle is inside right now.
const GEOFENCES = [
  { id: 1, d: "M56 66 L204 62 L208 176 L60 182 Z" },
  { id: 2, d: "M300 330 L452 326 L456 452 L304 456 Z", hot: true },
  { id: 3, d: "M442 478 L584 474 L588 604 L446 608 Z" },
  { id: 4, d: "M150 556 L304 552 L308 664 L154 668 Z" },
];

// Routes follow the street grid. Vehicles drive along these paths.
const ROUTES = [
  { id: "a", d: "M110 680 L110 400 L250 400 L250 120 L530 120" },
  { id: "b", d: "M530 680 L530 540 L250 540 L250 260 L110 260" },
  { id: "c", d: "M110 120 L390 120 L390 400 L530 400 L530 260" },
];

// dur = seconds per lap, begin = negative offset so vehicles are spread out,
// at = fixed position used when the person prefers reduced motion.
const VEHICLES = [
  { id: 1, route: "a", dur: 16, begin: 0, at: [110, 520] },
  { id: 2, route: "a", dur: 16, begin: -8, at: [250, 260] },
  { id: 3, route: "b", dur: 18, begin: 0, at: [530, 600] },
  { id: 4, route: "c", dur: 14, begin: 0, at: [390, 260] },
  { id: 5, route: "b", dur: 18, begin: -9, at: [250, 400], warn: true },
];

const STOPS = [
  [110, 400],
  [250, 120],
  [530, 120],
  [250, 540],
  [250, 260],
  [110, 260],
  [390, 400],
  [530, 400],
  [390, 120],
  [530, 540],
];

const LEGEND = [
  { key: "vehicles", label: "Live vehicles" },
  { key: "routes", label: "Routes" },
  { key: "geofences", label: "Geofences" },
  { key: "stops", label: "Stops" },
];

function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mq.matches);
    const onChange = () => setReduced(mq.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);
  return reduced;
}

type MapProps = {
  active: string | null;
};

function FleetMap({ active }: MapProps) {
  const reduced = usePrefersReducedMotion();
  // Dim any layer that is not the one hovered in the legend.
  const dim = (layers: string[]) =>
    active && !layers.includes(active) ? classes.dim : "";

  return (
    <svg
      className={classes.map}
      viewBox="0 0 620 740"
      preserveAspectRatio="xMidYMid slice"
      role="img"
      aria-label="Sample fleet map with vehicles, routes, geofences and stops"
    >
      <defs>
        <linearGradient id="scanGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#b8f0bf" stopOpacity="0" />
          <stop offset="1" stopColor="#b8f0bf" stopOpacity="0.25" />
        </linearGradient>
      </defs>

      <path className={classes.street} d={STREETS} />

      <g className={`${classes.layerGroup} ${dim(["geofences"])}`}>
        {GEOFENCES.map((g, i) => (
          <path
            key={g.id}
            d={g.d}
            pathLength={1}
            className={g.hot ? classes.geofenceHot : classes.geofence}
            style={{ animationDelay: `${i * 0.4}s` }}
          />
        ))}
      </g>

      <g className={`${classes.layerGroup} ${dim(["routes"])}`}>
        {ROUTES.map((r) => (
          <g key={r.id}>
            <path className={classes.routeBed} d={r.d} />
            <path className={classes.route} d={r.d} />
          </g>
        ))}
      </g>

      <rect className={classes.scan} x="0" y="0" width="620" height="60" />

      <g className={`${classes.stopGroup} ${dim(["stops"])}`}>
        {STOPS.map(([x, y], i) => (
          <g key={`${x}-${y}`}>
            <circle
              cx={x}
              cy={y}
              r={5}
              className={classes.stopPulse}
              style={{ animationDelay: `${1 + i * 0.35}s` }}
            />
            <circle cx={x} cy={y} r={5} className={classes.stop} />
          </g>
        ))}
      </g>

      <g className={`${classes.stopGroup} ${dim(["vehicles"])}`}>
        {VEHICLES.map((v) => {
          const route = ROUTES.find((r) => r.id === v.route)!;
          return (
            <g
              key={v.id}
              transform={
                reduced ? `translate(${v.at[0]} ${v.at[1]})` : undefined
              }
            >
              {!reduced && (
                <animateMotion
                  dur={`${v.dur}s`}
                  begin={`${v.begin}s`}
                  repeatCount="indefinite"
                  path={route.d}
                />
              )}
              <circle
                r={7}
                className={
                  v.warn ? classes.vehiclePulseWarn : classes.vehiclePulse
                }
              />
              <circle
                r={7}
                className={v.warn ? classes.vehicleWarn : classes.vehicle}
              />
            </g>
          );
        })}
      </g>
    </svg>
  );
}

type View = "login" | "forgot";

export default function Login() {
  const [view, setView] = useState<View>("login");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [layer, setLayer] = useState<string | null>(null);

  const form = useForm<{ email: string; password: string }>({
    initialValues: { email: "", password: "" },
    validate: {
      email: (val) =>
        /^\S+@\S+\.\S+$/.test(val) ? null : "Enter a valid email address",
      password: (val) => (val.length === 0 ? "Enter your password" : null),
    },
  });

  const forgotForm = useForm<{ email: string }>({
    initialValues: { email: "" },
    validate: {
      email: (val) =>
        /^\S+@\S+\.\S+$/.test(val) ? null : "Enter a valid email address",
    },
  });

  const switchView = (next: View) => {
    setErrorMessage(null);
    setSuccessMessage(null);
    setView(next);
  };

  const handleSubmit = async (values: { email: string; password: string }) => {
    try {
      setLoading(true);
      setErrorMessage(null);
      // TODO: sign in, then redirect. For example with Supabase:
      // const { error } = await supabase.auth.signInWithPassword({
      //   email: values.email,
      //   password: values.password,
      // });
      // if (error) throw error;
      // router.push('/');
      console.log("sign in", values.email);
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Something went wrong",
      );
    } finally {
      setLoading(false);
    }
  };

  const handleForgot = async (values: { email: string }) => {
    try {
      setLoading(true);
      setErrorMessage(null);
      setSuccessMessage(null);
      // TODO: send the reset link. For example with Supabase:
      // const { error } = await supabase.auth.resetPasswordForEmail(values.email);
      // if (error) throw error;
      console.log("reset", values.email);
      setSuccessMessage(
        "If an account matches, a reset link is on its way. Check your inbox.",
      );
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Something went wrong",
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className={classes.page}>
      <section className={classes.mapPanel}>
        <FleetMap active={layer} />
        <div className={classes.mapCopy}>
          <div className={classes.logo}>
            <span className={classes.logoMark}>
              <IconTruck size={22} stroke={2} />
            </span>
            <Text className={classes.brand}>Fleet</Text>
          </div>
          <Title order={2} className={classes.mapTitle}>
            Every vehicle, route, geofence and stop in one live view.
          </Title>
          <ul className={classes.legend}>
            {LEGEND.map((item) => (
              <li key={item.key}>
                <button
                  type="button"
                  className={classes.legendItem}
                  onMouseEnter={() => setLayer(item.key)}
                  onMouseLeave={() => setLayer(null)}
                  onFocus={() => setLayer(item.key)}
                  onBlur={() => setLayer(null)}
                >
                  <span
                    className={`${classes.swatch} ${classes[`sw_${item.key}`]}`}
                  />
                  {item.label}
                </button>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className={classes.formPanel}>
        {view === "login" ? (
          <form
            className={classes.form}
            onSubmit={form.onSubmit(handleSubmit)}
            autoComplete="on"
            noValidate
          >
            <Title order={1} className={classes.title}>
              Sign in
            </Title>
            <Text className={classes.subtitle}>
              Use your Fleet account to see where your vehicles are right now.
            </Text>

            {errorMessage && (
              <Alert
                color="red"
                variant="light"
                mt="md"
                title="Can't sign in"
                icon={<IconAlertCircle size={18} />}
              >
                {errorMessage}
              </Alert>
            )}

            <TextInput
              label="Email"
              placeholder="you@company.com"
              type="email"
              withAsterisk
              mt="lg"
              radius="sm"
              size="md"
              autoComplete="email"
              name="email"
              leftSection={<IconMail size={18} stroke={1.75} />}
              classNames={{
                label: classes.label,
                input: classes.input,
                section: classes.section,
              }}
              {...form.getInputProps("email")}
            />

            <PasswordInput
              label="Password"
              placeholder="Your password"
              withAsterisk
              mt="md"
              radius="sm"
              size="md"
              autoComplete="current-password"
              name="password"
              leftSection={<IconLock size={18} stroke={1.75} />}
              classNames={{
                label: classes.label,
                input: classes.input,
                innerInput: classes.innerInput,
                section: classes.section,
              }}
              {...form.getInputProps("password")}
            />

            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                marginTop: 16,
              }}
            >
              <Anchor
                component="button"
                type="button"
                size="sm"
                className={classes.link}
                onClick={() => switchView("forgot")}
              >
                <IconKey size={16} stroke={1.75} />
                Forgot password?
              </Anchor>
            </div>

            <Button
              fullWidth
              mt="xl"
              size="md"
              radius="sm"
              type="submit"
              loading={loading}
              className={classes.submit}
              leftSection={<IconLogin2 size={18} />}
            >
              Sign in
            </Button>
          </form>
        ) : (
          <form
            className={classes.form}
            onSubmit={forgotForm.onSubmit(handleForgot)}
            noValidate
          >
            <Title order={1} className={classes.title}>
              Reset your password
            </Title>
            <Text className={classes.subtitle}>
              Enter your email and we will send you a link to set a new
              password.
            </Text>

            {errorMessage && (
              <Alert
                color="red"
                variant="light"
                mt="md"
                title="Couldn't send the link"
                icon={<IconAlertCircle size={18} />}
              >
                {errorMessage}
              </Alert>
            )}
            {successMessage && (
              <Alert
                color="green"
                variant="light"
                mt="md"
                title="Link sent"
                icon={<IconCircleCheck size={18} />}
              >
                {successMessage}
              </Alert>
            )}

            <TextInput
              label="Email"
              placeholder="you@company.com"
              type="email"
              withAsterisk
              mt="lg"
              radius="sm"
              size="md"
              autoComplete="email"
              leftSection={<IconMail size={18} stroke={1.75} />}
              classNames={{
                label: classes.label,
                input: classes.input,
                section: classes.section,
              }}
              {...forgotForm.getInputProps("email")}
            />

            <Button
              fullWidth
              mt="xl"
              size="md"
              radius="sm"
              type="submit"
              loading={loading}
              className={classes.submit}
              leftSection={<IconSend size={18} />}
            >
              Send reset link
            </Button>

            <Anchor
              component="button"
              type="button"
              size="sm"
              mt="md"
              className={classes.link}
              onClick={() => switchView("login")}
            >
              <IconArrowLeft size={16} stroke={1.75} />
              Back to sign in
            </Anchor>
          </form>
        )}
      </section>
    </main>
  );
}

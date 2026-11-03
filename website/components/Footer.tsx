import { CHANGELOG_URL, DOWNLOAD_URL, GITHUB_URL, LICENSE_URL, RDPKIT_URL } from "@/lib/links";

const links = [
  { label: "Download", href: DOWNLOAD_URL },
  { label: "GitHub", href: GITHUB_URL },
  { label: "Changelog", href: CHANGELOG_URL },
  { label: "RDPKit", href: RDPKIT_URL },
  { label: "MIT License", href: LICENSE_URL },
];

export function Footer() {
  return (
    <footer className="border-t border-rule">
      <div className="mx-auto flex max-w-[72rem] flex-wrap items-center gap-x-8 gap-y-3 px-5 py-8 text-[14px] text-ink-3 sm:px-8">
        <p>
          © {new Date().getFullYear()}{" "}
          <a href="https://aneesiqbal.ai/" className="hover:text-ink">
            Anees Iqbal
          </a>
        </p>
        <nav aria-label="Footer" className="sm:ml-auto">
          <ul className="flex flex-wrap gap-x-5 gap-y-2">
            {links.map((link) => (
              <li key={link.label}>
                <a href={link.href} className="hover:text-ink">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </footer>
  );
}

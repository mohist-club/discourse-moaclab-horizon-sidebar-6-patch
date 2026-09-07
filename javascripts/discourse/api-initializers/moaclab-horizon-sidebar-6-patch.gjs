import { apiInitializer } from "discourse/lib/api";
import User from "discourse/models/user";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  const stackClass = "moac-horizon-sticky-stack";
  const fixedClass = "is-moac-horizon-fixed";
  const wrappedAttr = "data-moac-horizon-sticky-stack";
  const exclusiveGridClass = "moac-horizon-exclusive-subcategory-grid";
  const exclusiveFaqClass = "moac-horizon-exclusive-faq-latest";
  const subcategoryLogoClass = "moac-horizon-subcategory-logo";
  const faqLatestFallbackClass = "moac-horizon-faq-latest-fallback";
  const faqLatestFallbackAttr = "data-moac-horizon-faq-latest-fallback";
  const originalHeadingAttr = "data-moac-horizon-original-heading";
  const originalStickyTopAttr = "data-moac-horizon-original-sticky-top";
  const sidebarSelectors = [
    ".tc-right-sidebar",
    ".d-right-sidebar",
    ".right-sidebar",
    ".right-sidebar-blocks",
    ".sidebar-right",
    "aside[class*='sidebar']",
    "[class*='right-sidebar']",
  ].join(",");
  const blockSelectors = [
    ".rs-component",
    ".sidebar-block",
    ".right-sidebar-block",
    "[data-block-name]",
    "[data-name]",
    "section",
  ].join(",");
  const activitySelectors = [
    ".rs-component.rs-upcoming-events-list",
    ".rs-component[data-block-name='upcoming-events-list']",
    ".rs-component[data-name='upcoming-events-list']",
    ".rs-component[data-block-name='upcoming-events']",
    ".rs-component[data-name='upcoming-events']",
    ".rs-upcoming-events-list",
    ".rs-component.rs-calendar",
    ".rs-component[data-block-name='calendar']",
  ].join(",");
  const topTopicsSelectors = [
    ".rs-component.rs-top-topics",
    ".rs-component[data-block-name='top-topics']",
    ".rs-component[data-name='top-topics']",
    ".rs-top-topics",
  ].join(",");
  let frame = null;
  let observer = null;
  let applying = false;
  let stickyFrame = null;
  let categoryLogosPromise = null;
  let faqLatestPromise = null;
  let faqLatestKey = "";

  function guardAnonymousAttachmentClick(event) {
    if (User.current() || event.defaultPrevented) {
      return;
    }

    const link = event.target?.closest?.("a.attachment");
    if (!link) {
      return;
    }

    const siteSettings = api.container.lookup("service:site-settings");
    if (!siteSettings?.prevent_anons_from_downloading_files) {
      return;
    }

    // Discourse currently opens the warning but does not prevent the native
    // link navigation. Capture the click first so the protected URL never
    // replaces the topic with a 404 page.
    event.preventDefault();
    event.stopPropagation();

    api.container
      .lookup("service:dialog")
      .alert(i18n("post.errors.attachment_download_requires_login"));
  }

  function stickyTop() {
    const value = getComputedStyle(document.documentElement)
      .getPropertyValue("--moac-horizon-right-sidebar-sticky-top")
      .trim();

    return Number.parseFloat(value) || 86;
  }

  function clearFixedStack(stack) {
    stack.classList.remove(fixedClass);
    stack.style.left = "";
    stack.style.top = "";
    stack.style.width = "";
  }

  function unwrapStack(stack) {
    const parent = stack.parentElement;
    if (!parent) {
      return;
    }
    [...stack.children].forEach((child) => parent.insertBefore(child, stack));
    stack.remove();
  }

  function blockTitleText(element) {
    return (
      element.querySelector(
        "h1, h2, h3, .rs-component-title, .sidebar-block-title, .block-title, [class*='title']",
      )?.textContent || ""
    ).trim();
  }

  function directSidebarChild(node, sidebar) {
    let current = node;

    while (current && current.parentElement !== sidebar) {
      current = current.parentElement;
    }

    return current?.parentElement === sidebar ? current : null;
  }

  function nearestBlock(node, sidebar) {
    const block = node.closest(blockSelectors);
    return block && sidebar.contains(block)
      ? directSidebarChild(block, sidebar) || block
      : directSidebarChild(node, sidebar);
  }

  function findActivityBlock(sidebar) {
    const directMatch = sidebar.querySelector(activitySelectors);
    if (directMatch) {
      return nearestBlock(directMatch, sidebar);
    }

    const blockMatch = [...sidebar.querySelectorAll(blockSelectors)].find(
      (block) => /近期活动|活动|Upcoming|Events/i.test(blockTitleText(block)),
    );
    if (blockMatch) {
      return nearestBlock(blockMatch, sidebar);
    }

    const textMatch = [...sidebar.children].find((child) =>
      /近期活动|Upcoming Events|Events/i.test(child.textContent || ""),
    );
    if (textMatch) {
      return textMatch;
    }

    const topTopics = sidebar.querySelector(topTopicsSelectors);
    const topTopicsBlock = topTopics ? nearestBlock(topTopics, sidebar) : null;
    return topTopicsBlock?.nextElementSibling || null;
  }

  function applyStickyStack() {
    if (applying) {
      return;
    }

    const sidebar = document.querySelector(sidebarSelectors);
    if (!sidebar) {
      return;
    }

    const existingStack = sidebar.querySelector(`.${stackClass}`);
    if (existingStack?.children.length) {
      scheduleStickyUpdate();
      return;
    }

    applying = true;
    document.querySelectorAll(`.${stackClass}`).forEach(unwrapStack);

    const activityBlock = findActivityBlock(sidebar);
    if (!activityBlock || !activityBlock.parentElement) {
      applying = false;
      return;
    }

    const parent = activityBlock.parentElement;
    const siblings = [...parent.children];
    const startIndex = siblings.indexOf(activityBlock);
    if (startIndex < 0) {
      applying = false;
      return;
    }

    const stack = document.createElement("div");
    stack.className = stackClass;
    stack.setAttribute(wrappedAttr, "true");
    parent.insertBefore(stack, activityBlock);

    siblings.slice(startIndex).forEach((child) => {
      if (child !== stack && child.parentElement === parent) {
        stack.appendChild(child);
      }
    });

    applying = false;
    scheduleStickyUpdate();
  }

  function updateStickyPosition() {
    const stack = document.querySelector(`.${stackClass}`);
    const sidebar = stack?.closest(sidebarSelectors);
    if (!stack || !sidebar || window.matchMedia("(max-width: 960px)").matches) {
      if (stack) {
        clearFixedStack(stack);
      }
      return;
    }

    const wasFixed = stack.classList.contains(fixedClass);

    if (wasFixed) {
      clearFixedStack(stack);
    }

    const stackRect = stack.getBoundingClientRect();
    const sidebarRect = sidebar.getBoundingClientRect();
    const exclusiveSticky =
      document.body.classList.contains(exclusiveGridClass) ||
      document.body.classList.contains(exclusiveFaqClass);
    let top = stickyTop();

    if (exclusiveSticky) {
      const storedTop = Number.parseFloat(
        stack.getAttribute(originalStickyTopAttr),
      );

      if (Number.isFinite(storedTop)) {
        top = storedTop;
      } else {
        top = Math.max(top, stackRect.top + window.scrollY);
        stack.setAttribute(originalStickyTopAttr, String(top));
      }
    } else {
      stack.removeAttribute(originalStickyTopAttr);
    }

    const startY = stackRect.top + window.scrollY - top;

    if (window.scrollY >= startY) {
      stack.classList.add(fixedClass);
      stack.style.left = `${sidebarRect.left}px`;
      stack.style.top = `${top}px`;
      stack.style.width = `${sidebarRect.width}px`;
    }
  }

  function scheduleStickyUpdate() {
    cancelAnimationFrame(stickyFrame);
    stickyFrame = requestAnimationFrame(updateStickyPosition);
  }

  function configuredCategoryIds(value) {
    const values = Array.isArray(value)
      ? value
      : String(value || "").split(/[|,]/);

    return values
      .map((item) =>
        Number(
          typeof item === "object" && item !== null
            ? (item.id ?? item.value)
            : item,
        ),
      )
      .filter(Number.isFinite);
  }

  function currentCategoryId() {
    return Number(
      api.container.lookup("service:router").currentRoute?.attributes?.category
        ?.id,
    );
  }

  function logoMap(categories = []) {
    return new Map(
      categories
        .map((category) => [
          Number(category.id),
          category.uploaded_logo?.url || category.logo_url || null,
        ])
        .filter(([, logoUrl]) => logoUrl),
    );
  }

  function localCategoryLogos() {
    const routeCategory =
      api.container.lookup("service:router").currentRoute?.attributes?.category;
    const site = api.container.lookup("service:site");

    return logoMap([
      ...(site?.categories || []),
      ...(routeCategory?.subcategories || []),
    ]);
  }

  function categoryLogos() {
    const localLogos = localCategoryLogos();

    categoryLogosPromise ??= fetch("/site.json", {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Unable to load category logos (${response.status})`);
        }
        return response.json();
      })
      .then((site) => {
        const categories =
          site.categories || site.category_list?.categories || [];
        return logoMap(categories);
      })
      .catch(() => new Map());

    return categoryLogosPromise.then(
      (remoteLogos) => new Map([...localLogos, ...remoteLogos]),
    );
  }

  function nativeFaqLatestHasTopics(sidebar) {
    return Boolean(
      sidebar.querySelector(
        `.rs-component.rs-category-topics:not(.${faqLatestFallbackClass}) .category-topics--topic`,
      ),
    );
  }

  function faqLatestContainer(sidebar) {
    const stack = sidebar.querySelector(`.${stackClass}`);
    return stack || sidebar;
  }

  function removeFaqLatestFallback() {
    document
      .querySelectorAll(`.${faqLatestFallbackClass}`)
      .forEach((block) => block.remove());
  }

  function normalizeFaqLatestPath(path) {
    const trimmed = String(path || "").trim() || "/c/faq/4.json";
    return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  }

  function cachedFaqLatest(path, count) {
    try {
      const cached = JSON.parse(
        localStorage.getItem(`moac-horizon-faq-latest:${path}:${count}`),
      );

      if (cached && Date.now() - cached.savedAt < 5 * 60 * 1000) {
        return cached.topics;
      }
    } catch {
      return null;
    }

    return null;
  }

  function saveFaqLatestCache(path, count, topics) {
    try {
      localStorage.setItem(
        `moac-horizon-faq-latest:${path}:${count}`,
        JSON.stringify({ savedAt: Date.now(), topics }),
      );
    } catch {
      // Private browsing or storage limits should not block rendering.
    }
  }

  async function loadFaqLatestTopics() {
    const path = normalizeFaqLatestPath(settings.faq_latest_source_path);
    const count = Number(settings.faq_latest_count) || 5;
    const key = `${path}:${count}`;
    const cached = cachedFaqLatest(path, count);

    if (cached) {
      return cached;
    }

    if (faqLatestPromise && faqLatestKey === key) {
      return faqLatestPromise;
    }

    faqLatestKey = key;
    faqLatestPromise = fetch(path, {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Unable to load latest Q&A (${response.status})`);
        }
        return response.json();
      })
      .then((payload) => {
        const topics = (payload.topic_list?.topics || [])
          .filter((topic) => !topic.deleted)
          .slice(0, count)
          .map((topic) => ({
            id: topic.id,
            slug: topic.slug,
            title: topic.fancy_title || topic.title,
            replies: topic.reply_count ?? Math.max((topic.posts_count || 1) - 1, 0),
          }));
        saveFaqLatestCache(path, count, topics);
        return topics;
      })
      .catch(() => []);

    return faqLatestPromise;
  }

  function renderFaqLatestFallback(sidebar, topics) {
    if (!document.body.classList.contains(exclusiveFaqClass)) {
      return;
    }

    if (nativeFaqLatestHasTopics(sidebar)) {
      removeFaqLatestFallback();
      return;
    }

    const container = faqLatestContainer(sidebar);
    let block = container.querySelector(`.${faqLatestFallbackClass}`);

    if (!topics.length) {
      removeFaqLatestFallback();
      return;
    }

    if (!block) {
      block = document.createElement("section");
      block.className = `rs-component rs-category-topics ${faqLatestFallbackClass}`;
      block.setAttribute(faqLatestFallbackAttr, "true");
      container.prepend(block);
    }

    const content = document.createElement("div");
    content.className = "category-topics--content";

    topics.forEach((topic) => {
      const link = document.createElement("a");
      link.className = "category-topics--topic";
      link.href = `/t/${topic.slug || "topic"}/${topic.id}`;

      const title = document.createElement("span");
      title.className = "category-topics--title";
      title.textContent = topic.title || "未命名话题";

      const count = document.createElement("span");
      count.className = "category-topics--posts-count";
      count.textContent = `${topic.replies || 0} 回复`;

      link.append(title, count);
      content.append(link);
    });

    block.replaceChildren(content);
  }

  function ensureFaqLatestFallback() {
    const sidebar = document.querySelector(sidebarSelectors);

    if (!sidebar || !document.body.classList.contains(exclusiveFaqClass)) {
      removeFaqLatestFallback();
      return;
    }

    if (nativeFaqLatestHasTopics(sidebar)) {
      removeFaqLatestFallback();
      return;
    }

    loadFaqLatestTopics().then((topics) => renderFaqLatestFallback(sidebar, topics));
  }

  async function enhanceSubcategoryGrid() {
    const logos = await categoryLogos();

    document
      .querySelectorAll(
        ".rs-component.rs-subcategory-list .subcategory-list--item a.badge-category__wrapper",
      )
      .forEach((link) => {
        const categoryId = Number(
          link.querySelector("[data-category-id]")?.dataset.categoryId,
        );
        const logoUrl = logos.get(categoryId);
        let logo = link.querySelector(`.${subcategoryLogoClass}`);

        if (!logo) {
          logo = document.createElement("span");
          logo.className = subcategoryLogoClass;
          logo.setAttribute("aria-hidden", "true");
          link.prepend(logo);
        }

        if (logoUrl && !logo.querySelector("img")) {
          const image = document.createElement("img");
          image.alt = "";
          image.loading = "lazy";
          image.decoding = "async";
          image.src = logoUrl;
          logo.replaceChildren(image);
          return;
        }

        if (!logoUrl && !logo.hasChildNodes()) {
          const fallbackIcon = link.querySelector(".badge-category .d-icon");
          if (fallbackIcon) {
            logo.appendChild(fallbackIcon.cloneNode(true));
          }
        }
      });
  }

  function updateCategorySpecificSidebar() {
    const categoryIds = configuredCategoryIds(
      settings.exclusive_subcategory_grid_categories,
    );
    const enabled =
      settings.enable_exclusive_subcategory_grid &&
      categoryIds.includes(currentCategoryId());

    document.body.classList.toggle(exclusiveGridClass, enabled);

    document
      .querySelectorAll(
        ".rs-component.rs-subcategory-list .subcategory-list--heading",
      )
      .forEach((heading) => {
        if (enabled) {
          if (!heading.hasAttribute(originalHeadingAttr)) {
            heading.setAttribute(
              originalHeadingAttr,
              heading.textContent.trim(),
            );
          }
          heading.textContent = settings.subcategory_grid_heading || "工作室";
          return;
        }

        if (heading.hasAttribute(originalHeadingAttr)) {
          heading.textContent = heading.getAttribute(originalHeadingAttr);
          heading.removeAttribute(originalHeadingAttr);
        }
      });

    if (!enabled) {
      document
        .querySelectorAll(`.${stackClass}`)
        .forEach((stack) => stack.removeAttribute(originalStickyTopAttr));
      document
        .querySelectorAll(`.${subcategoryLogoClass}`)
        .forEach((logo) => logo.remove());
      return;
    }

    enhanceSubcategoryGrid();
  }

  function updateFaqLatestSidebar() {
    const categoryIds = configuredCategoryIds(
      settings.exclusive_faq_latest_categories,
    );
    const enabled =
      settings.enable_exclusive_faq_latest &&
      categoryIds.includes(currentCategoryId()) &&
      !document.body.classList.contains(exclusiveGridClass);

    document.body.classList.toggle(exclusiveFaqClass, enabled);

    if (enabled) {
      ensureFaqLatestFallback();
    } else {
      removeFaqLatestFallback();
    }
  }

  function applyEnhancements() {
    if (settings.enable_right_sidebar_sticky_stack) {
      applyStickyStack();
    }
    updateCategorySpecificSidebar();
    updateFaqLatestSidebar();
  }

  function scheduleApply() {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(applyEnhancements);
  }

  function ensureObserver() {
    if (observer || !document.body) {
      return;
    }
    observer = new MutationObserver(scheduleApply);
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (settings.prevent_anonymous_attachment_404) {
    document.addEventListener("click", guardAnonymousAttachmentClick, true);
  }

  if (
    settings.enable_right_sidebar_sticky_stack ||
    settings.enable_exclusive_subcategory_grid ||
    settings.enable_exclusive_faq_latest
  ) {
    api.onPageChange(() => {
      document
        .querySelectorAll(`.${stackClass}`)
        .forEach((stack) => stack.removeAttribute(originalStickyTopAttr));
      scheduleApply();
    });
    ensureObserver();
    scheduleApply();
  }

  if (settings.enable_right_sidebar_sticky_stack) {
    window.addEventListener("scroll", scheduleStickyUpdate, { passive: true });
    window.addEventListener("resize", () => {
      document
        .querySelectorAll(`.${stackClass}`)
        .forEach((stack) => stack.removeAttribute(originalStickyTopAttr));
      scheduleStickyUpdate();
    });
  }
});

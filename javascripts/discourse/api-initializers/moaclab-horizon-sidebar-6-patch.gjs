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
  const faqModuleClass = "moac-horizon-faq-latest";
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
  let faqLatestSourceId = null;

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

  function latestFaqTopics(sourceCategoryId) {
    if (faqLatestSourceId !== sourceCategoryId) {
      faqLatestSourceId = sourceCategoryId;
      faqLatestPromise = null;
    }

    faqLatestPromise ??= fetch(`/c/faq/${sourceCategoryId}.json`, {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(
            `Unable to load latest Q&A topics (${response.status})`,
          );
        }
        return response.json();
      })
      .then((category) => category.topic_list?.topics || [])
      .catch(() => null);

    return faqLatestPromise;
  }

  function topicUrl(topic) {
    const slug = encodeURIComponent(topic.slug || "topic");
    return `/t/${slug}/${topic.id}`;
  }

  function relativeTime(dateString) {
    const timestamp = Date.parse(dateString);
    if (!Number.isFinite(timestamp)) {
      return "";
    }

    const elapsedSeconds = Math.max(0, (Date.now() - timestamp) / 1000);
    const units = [
      ["year", 365 * 24 * 60 * 60],
      ["month", 30 * 24 * 60 * 60],
      ["day", 24 * 60 * 60],
      ["hour", 60 * 60],
      ["minute", 60],
    ];
    const locale = document.documentElement.lang || "zh-CN";
    const formatter = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });

    for (const [unit, seconds] of units) {
      if (elapsedSeconds >= seconds) {
        return formatter.format(-Math.floor(elapsedSeconds / seconds), unit);
      }
    }

    return formatter.format(0, "second");
  }

  function createFaqLatestModule() {
    const module = document.createElement("section");
    module.className = `rs-component ${faqModuleClass}`;
    module.setAttribute("aria-labelledby", "moac-horizon-faq-latest-heading");

    const heading = document.createElement("h2");
    heading.id = "moac-horizon-faq-latest-heading";
    heading.className = "moac-horizon-faq-latest__heading";
    heading.textContent = settings.faq_latest_heading || "最新问答";

    const status = document.createElement("p");
    status.className = "moac-horizon-faq-latest__status";
    status.setAttribute("role", "status");
    status.setAttribute("aria-live", "polite");
    status.textContent = "正在加载…";

    module.append(heading, status);
    return module;
  }

  function placeFaqLatestModule(module, sidebar) {
    let stack = sidebar.querySelector(`.${stackClass}`);

    if (!stack) {
      stack = document.createElement("div");
      stack.className = stackClass;
      stack.setAttribute(wrappedAttr, "true");
      sidebar.prepend(stack);
    }

    if (module.parentElement !== stack) {
      stack.prepend(module);
    }

    scheduleStickyUpdate();
  }

  async function renderFaqLatestModule(module, sourceCategoryId) {
    if (
      module.dataset.state === "loading" ||
      module.dataset.state === "loaded"
    ) {
      return;
    }

    module.dataset.state = "loading";
    const sourceKey = module.dataset.sourceKey;
    const [topics, logos] = await Promise.all([
      latestFaqTopics(sourceCategoryId),
      categoryLogos(),
    ]);
    if (!module.isConnected || module.dataset.sourceKey !== sourceKey) {
      return;
    }

    const limit = Math.max(1, Number(settings.faq_latest_topic_limit) || 5);
    const status = module.querySelector(".moac-horizon-faq-latest__status");
    if (!status) {
      return;
    }

    if (!topics) {
      status.textContent = "暂时无法加载，请稍后刷新";
      module.dataset.state = "error";
      return;
    }

    const visibleTopics = topics.slice(0, limit);

    if (!visibleTopics.length) {
      status.textContent = "暂时没有问答话题";
      module.dataset.state = "loaded";
      return;
    }

    const list = document.createElement("ul");
    list.className = "moac-horizon-faq-latest__list";
    const sourceLabel = settings.faq_latest_source_label || "问答/求助";
    const sourceLogoUrl = logos.get(sourceCategoryId);

    visibleTopics.forEach((topic) => {
      const item = document.createElement("li");
      item.className = "moac-horizon-faq-latest__item";

      const link = document.createElement("a");
      link.className = "moac-horizon-faq-latest__link";
      link.href = topicUrl(topic);

      const source = document.createElement("span");
      source.className = "moac-horizon-faq-latest__source";

      const logo = document.createElement("span");
      logo.className = "moac-horizon-faq-latest__logo";
      logo.setAttribute("aria-hidden", "true");

      if (sourceLogoUrl) {
        const image = document.createElement("img");
        image.alt = "";
        image.loading = "lazy";
        image.decoding = "async";
        image.src = sourceLogoUrl;
        logo.appendChild(image);
      } else {
        logo.textContent = "?";
      }

      const sourceName = document.createElement("strong");
      sourceName.textContent = sourceLabel;

      const separator = document.createElement("span");
      separator.className = "moac-horizon-faq-latest__separator";
      separator.setAttribute("aria-hidden", "true");
      separator.textContent = "·";

      const activityDate = topic.last_posted_at || topic.created_at;
      const time = document.createElement("time");
      time.dateTime = activityDate;
      time.textContent = relativeTime(activityDate);

      source.append(logo, sourceName, separator, time);

      const title = document.createElement("span");
      title.className = "moac-horizon-faq-latest__title";
      title.textContent = topic.unicode_title || topic.title;

      const metrics = document.createElement("span");
      metrics.className = "moac-horizon-faq-latest__metrics";
      metrics.textContent = `${topic.like_count || 0} 点赞 · ${topic.reply_count || 0} 评论`;

      link.append(source, title, metrics);

      item.appendChild(link);
      list.appendChild(item);
    });

    status.replaceWith(list);
    module.dataset.state = "loaded";
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

    const sidebar = document.querySelector(sidebarSelectors);
    const existingModule = document.querySelector(`.${faqModuleClass}`);

    if (!enabled || !sidebar) {
      existingModule?.remove();
      return;
    }

    const sourceCategoryId =
      Number(settings.faq_latest_source_category_id) || 4;
    const sourceKey = `${sourceCategoryId}:${settings.faq_latest_topic_limit}:${settings.faq_latest_heading}:${settings.faq_latest_source_label}`;
    let module = existingModule;

    if (module?.dataset.sourceKey !== sourceKey) {
      module?.remove();
      module = null;
    }

    module ??= createFaqLatestModule();
    module.dataset.sourceKey = sourceKey;
    placeFaqLatestModule(module, sidebar);

    if (!module.dataset.state) {
      renderFaqLatestModule(module, sourceCategoryId);
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

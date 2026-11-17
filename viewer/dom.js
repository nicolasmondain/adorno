// Two element builders. Text always goes through textContent or a text node: what a journal holds (commands,
// prompts, names) is never parsed as markup.

const SVG = "http://www.w3.org/2000/svg";

function fill(node, attrs, children) {
  for (const [name, value] of Object.entries(attrs || {})) {
    if (value === null || value === undefined || value === false) continue;
    if (name === "text") node.textContent = value;
    else if (name === "on") for (const [type, handler] of Object.entries(value)) node.addEventListener(type, handler);
    else node.setAttribute(name, value === true ? "" : value);
  }
  for (const child of children) if (child !== null && child !== undefined && child !== false) node.append(child);
  return node;
}

// el("button", {class: "x", text: "Play", on: {click}}, child…)
export function el(name, attrs, ...children) {
  return fill(document.createElement(name), attrs, children);
}

export function svg(name, attrs, ...children) {
  return fill(document.createElementNS(SVG, name), attrs, children);
}
